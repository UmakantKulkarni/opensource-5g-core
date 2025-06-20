#!/usr/bin/env python3

import os
import yaml
import argparse
import subprocess
import json
from flask import Flask, request, jsonify, render_template

app = Flask(__name__)

# Paths
my_dir_path = os.path.dirname(os.path.realpath(__file__))
VALUES_YML_PATH = os.path.join(my_dir_path, "values.yaml")
UPDATED_YML_PATH = os.path.join(my_dir_path, "updated_values.yaml")


# Function to infer correct default values for all types
def infer_default_value(value):
    """Infer the correct default value based on type."""
    if isinstance(value, str):
        return ""  # Empty string
    elif isinstance(value, int):
        return 0  # Default 0 for integers
    elif isinstance(value, float):
        return 0.0  # Default 0.0 for floats
    elif isinstance(value, bool):
        return False  # Default False for booleans
    elif isinstance(value, list):
        return []  # Empty list
    elif isinstance(value, dict):
        return {
            k: infer_default_value(v)
            for k, v in value.items()
        }  # Recursive
    else:
        return None  # Default None for unknown types


# Generate templates dynamically for arrays
def generate_templates(data):
    templates = {}

    def recursive_template(obj, key_path=""):
        if isinstance(obj, list) and len(obj) > 0 and isinstance(obj[0], dict):
            templates[key_path] = {
                k: infer_default_value(v)
                for k, v in obj[0].items()
            }
        elif isinstance(obj, dict):
            for key, value in obj.items():
                recursive_template(value,
                                   f"{key_path}.{key}" if key_path else key)

    recursive_template(data)
    return templates


def deep_update(base, updates):
    """Recursively update a dict with another dict."""
    for key, value in updates.items():
        if (
            isinstance(value, dict)
            and key in base
            and isinstance(base[key], dict)
        ):
            deep_update(base[key], value)
        else:
            base[key] = value


def namespace_exists(namespace, kubectl_config):
    """Check if a Kubernetes namespace exists."""
    command = f"kubectl --kubeconfig={kubectl_config} get namespace {namespace} --no-headers"
    result = subprocess.run(command,
                            shell=True,
                            capture_output=True,
                            text=True)
    return result.returncode == 0


def create_namespace(namespace, kubectl_config):
    """Create a Kubernetes namespace if it doesn't exist."""
    command = f"kubectl --kubeconfig={kubectl_config} create namespace {namespace}"
    subprocess.run(command, shell=True)


def helm_release_exists(namespace, release_name):
    """Check if a Helm release exists in the specified namespace."""
    try:
        command = f"helm -n {namespace} ls --filter {release_name} --output json"
        result = subprocess.run(command,
                                shell=True,
                                capture_output=True,
                                text=True)

        if result.returncode != 0:
            return False

        try:
            releases = json.loads(result.stdout)
        except json.JSONDecodeError:
            return False

        return any(r.get("name") == release_name for r in releases)
    except Exception as e:
        print(f"Error checking Helm release: {e}")
        return False


@app.route("/")
def landing():
    """Landing page with navigation options."""
    return render_template("landing.html")


@app.route("/create")
def create():
    """Render form for creating or updating deployments."""
    namespace = request.args.get("namespace", "default")
    release = request.args.get("release", "5gcore")
    mode = request.args.get("mode", "create")

    with open(VALUES_YML_PATH, "r") as file:
        default_values = yaml.safe_load(file)

    # If updating and release exists, preload values from the Helm release
    values = default_values
    if mode == "update" and helm_release_exists(namespace, release):
        cmd = f"helm -n {namespace} get values {release}"
        proc = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if proc.returncode == 0 and proc.stdout:
            try:
                release_values = yaml.safe_load(proc.stdout)
                if isinstance(release_values, dict):
                    deep_update(values, release_values)
            except yaml.YAMLError:
                pass

    templates = generate_templates(default_values)

    return render_template(
        "index.html",
        values=values,
        templates=templates,
    )


@app.route("/manage")
def manage():
    """Page for managing existing deployments."""
    return render_template("manage.html")


@app.route("/release_exists")
def release_exists_route():
    """Return whether a Helm release exists."""
    namespace = request.args.get("namespace", "default")
    release = request.args.get("release", "5gcore")
    exists = helm_release_exists(namespace, release)
    return jsonify({"exists": exists})


@app.route("/update", methods=["POST"])
def update_values():
    data = request.json

    # Extract Helm-specific inputs
    namespace = data.pop("helmNamespace", "default")
    release_name = data.pop("helmReleaseName", "5gcore")
    helm_chart_path = data.pop("helmChartPath",
                               "/opt/opensource-5g-core/helm-chart")
    kubectl_config = data.pop("kubectlConfigPath",
                              "/etc/kubernetes/admin.conf")

    # Check if namespace exists, and create it if necessary
    if not namespace_exists(namespace, kubectl_config):
        create_namespace(namespace, kubectl_config)

    # Check if the Helm release already exists
    release_exists = helm_release_exists(namespace, release_name)

    # Save updated YAML values
    with open(UPDATED_YML_PATH, "w") as file:
        yaml.safe_dump(data, file)

    # Determine whether to install or upgrade
    if release_exists:
        # Prompt user for upgrade or abort
        return jsonify({
            "status":
            "exists",
            "message":
            f"The Helm release '{release_name}' already exists in namespace '{namespace}'. Do you want to upgrade?",
        })

    # Helm install
    command = (
        f"helm -n {namespace} install {release_name} -f {UPDATED_YML_PATH} {helm_chart_path}"
    )
    process = subprocess.run(command,
                             shell=True,
                             capture_output=True,
                             text=True)

    if process.returncode != 0:
        return jsonify({"status": "error", "output": process.stderr})

    return jsonify({"status": "success", "output": process.stdout})


@app.route("/upgrade", methods=["POST"])
def upgrade_release():
    data = request.json

    # Extract Helm-specific inputs
    namespace = data.pop("helmNamespace", "default")
    release_name = data.pop("helmReleaseName", "5gcore")
    helm_chart_path = data.pop("helmChartPath",
                               "/opt/opensource-5g-core/helm-chart")

    # Helm upgrade
    command = (
        f"helm -n {namespace} upgrade {release_name} -f {UPDATED_YML_PATH} {helm_chart_path}"
    )
    process = subprocess.run(command,
                             shell=True,
                             capture_output=True,
                             text=True)

    if process.returncode != 0:
        return jsonify({"status": "error", "output": process.stderr})

    return jsonify({"status": "success", "output": process.stdout})


@app.route("/delete", methods=["POST"])
def delete_release():
    """Delete an existing Helm release."""
    data = request.json
    namespace = data.get("helmNamespace", "default")
    release_name = data.get("helmReleaseName", "5gcore")

    command = f"helm -n {namespace} uninstall {release_name}"
    process = subprocess.run(command,
                             shell=True,
                             capture_output=True,
                             text=True)

    if process.returncode != 0:
        return jsonify({"status": "error", "output": process.stderr})

    return jsonify({"status": "success", "output": process.stdout})


@app.route("/releases")
def list_releases():
    """Return list of all Helm releases across namespaces."""
    command = "helm ls -A --output json"
    process = subprocess.run(command,
                             shell=True,
                             capture_output=True,
                             text=True)
    if process.returncode != 0:
        return jsonify([])
    try:
        releases = json.loads(process.stdout)
    except json.JSONDecodeError:
        return jsonify([])
    return jsonify(releases)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        __doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--server_ip', '-s', default="0.0.0.0")
    parser.add_argument('--server_port', '-p', default=15001)
    args = parser.parse_args()
    app.run(host=args.server_ip, port=args.server_port)
