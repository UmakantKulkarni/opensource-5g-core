#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Simple Open5GS UERANSIM control script
#
# This script runs on the Kubernetes node.
# It uses kubectl exec to run commands inside the open5gs-test pod.
###############################################################################

###############################################################################
# Customizable values
###############################################################################

TEST_POD_PATTERN="open5gs-test-deployment"
TEST_CONTAINER="test"

SUBSCRIBER_COUNT="5"
AMF_ADDRESS="amf-open5gs-sctp"

SCRIPTS_DIR="/root/scripts"
UERANSIM_DIR="/root/UERANSIM"

GNB_CONFIG="/root/UERANSIM/config/open5gs-gnb.yaml"
UE_CONFIG="/root/UERANSIM/config/open5gs-ue.yaml"

TUN_IF="uesimtun0"
PING_TARGET="10.45.0.1"

WAIT_SECONDS="30"

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
  $0 <namespace> --configure
  $0 <namespace> --startgnb
  $0 <namespace> --startue
  $0 <namespace> --cleanall
  $0 <namespace> --all

Examples:
  $0 noztx5gc --configure
  $0 noztx5gc --startgnb
  $0 noztx5gc --startue
  $0 noztx5gc --cleanall
  $0 noztx5gc --all

Options:
  --configure   Add Mongo subscribers and update open5gs-gnb.yaml
  --startgnb    Kill existing nr-gnb and start a new nr-gnb in background
  --startue     Kill existing ping and nr-ue, start nr-ue in background,
                wait for UE TUN IP, then start ping in foreground
  --cleanall    Kill ping, nr-ue, and nr-gnb inside the test container
  --all         Run configure, startgnb, and startue in order
  -h, --help    Show this help

EOF
}

###############################################################################
# Local helper functions
###############################################################################

log() {
    echo "[$(date '+%F %T')] $*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

find_test_pod() {
    kubectl get pods -n "$NAMESPACE" \
        --no-headers \
        -o custom-columns=NAME:.metadata.name,PHASE:.status.phase \
        | awk -v pattern="$TEST_POD_PATTERN" '
            $1 ~ pattern && $2 == "Running" {
                print $1
                exit
            }
        '
}

run_inside_test_container() {
    kubectl exec -i -n "$NAMESPACE" "$POD_NAME" -c "$TEST_CONTAINER" -- bash -s -- "$@"
}

###############################################################################
# Configure Mongo subscribers and GNodeB config
###############################################################################

configure() {
    log "Configuring Mongo subscribers and GNodeB config..."

    run_inside_test_container \
        "$SUBSCRIBER_COUNT" \
        "$AMF_ADDRESS" \
        "$SCRIPTS_DIR" \
        "$GNB_CONFIG" <<'IN_CONTAINER'

set -e

SUBSCRIBER_COUNT="$1"
AMF_ADDRESS="$2"
SCRIPTS_DIR="$3"
GNB_CONFIG="$4"

echo "Adding Mongo subscribers..."

cd "$SCRIPTS_DIR"

if ./addMongoSubs.py "$SUBSCRIBER_COUNT"; then
    echo "Mongo subscribers added successfully."
else
    echo "WARNING: addMongoSubs.py returned an error."
    echo "Continuing because subscribers may already exist."
fi

echo "Updating GNodeB config..."

POD_IP="${MY_POD_IP:-}"

if [ -z "$POD_IP" ]; then
    POD_IP="$(hostname -i | awk '{print $1}')"
fi

if [ -z "$POD_IP" ]; then
    echo "ERROR: Could not determine pod IP."
    exit 1
fi

if [ ! -f "$GNB_CONFIG" ]; then
    echo "ERROR: GNodeB config not found: $GNB_CONFIG"
    exit 1
fi

if [ ! -f "${GNB_CONFIG}.bak.original" ]; then
    cp "$GNB_CONFIG" "${GNB_CONFIG}.bak.original"
    echo "Backup created: ${GNB_CONFIG}.bak.original"
fi

sed -i -E \
    -e "s|^([[:space:]]*ngapIp:[[:space:]]*).*|\1${POD_IP}   # gNB's local IP address for N2 Interface (Usually same with local IP)|" \
    -e "s|^([[:space:]]*gtpIp:[[:space:]]*).*|\1${POD_IP}   # gNB's local IP address for N3 Interface (Usually same with local IP)|" \
    -e "s|^([[:space:]]*-[[:space:]]*address:[[:space:]]*).*|\1${AMF_ADDRESS}|" \
    "$GNB_CONFIG"

echo "GNodeB config updated."
echo
grep -E '^(linkIp|ngapIp|gtpIp):|^[[:space:]]*-[[:space:]]*address:' "$GNB_CONFIG" || true

IN_CONTAINER
}

###############################################################################
# Start GNodeB
###############################################################################

start_gnb() {
    log "Starting GNodeB..."

    run_inside_test_container \
        "$UERANSIM_DIR" \
        "$GNB_CONFIG" \
        "$WAIT_SECONDS" <<'IN_CONTAINER'

set -e

UERANSIM_DIR="$1"
GNB_CONFIG="$2"
WAIT_SECONDS="$3"

LOG_DIR="/tmp/ueransim-control"
GNB_LOG="$LOG_DIR/nr-gnb.log"

mkdir -p "$LOG_DIR"

echo "Stopping existing nr-gnb process, if any..."
pkill -f "nr-gnb" 2>/dev/null || true
sleep 1
pkill -9 -f "nr-gnb" 2>/dev/null || true

if [ ! -d "$UERANSIM_DIR" ]; then
    echo "ERROR: UERANSIM directory not found: $UERANSIM_DIR"
    exit 1
fi

if [ ! -f "$GNB_CONFIG" ]; then
    echo "ERROR: GNodeB config not found: $GNB_CONFIG"
    exit 1
fi

cd "$UERANSIM_DIR"

echo "Starting nr-gnb in background..."
: > "$GNB_LOG"

nohup nr-gnb -c "$GNB_CONFIG" > "$GNB_LOG" 2>&1 &
GNB_PID="$!"

echo "nr-gnb PID: $GNB_PID"
echo "Waiting for successful NG Setup..."

for i in $(seq 1 "$WAIT_SECONDS"); do
    if grep -q "NG Setup procedure is successful" "$GNB_LOG"; then
        echo "GNodeB is connected."
        exit 0
    fi

    if ! kill -0 "$GNB_PID" 2>/dev/null; then
        echo "ERROR: nr-gnb exited before connecting."
        echo
        tail -50 "$GNB_LOG" || true
        exit 1
    fi

    sleep 1
done

echo "ERROR: GNodeB did not connect within ${WAIT_SECONDS} seconds."
echo
tail -50 "$GNB_LOG" || true
exit 1

IN_CONTAINER
}

###############################################################################
# Start UE and ping
###############################################################################

start_ue() {
    log "Starting UE..."

    run_inside_test_container \
        "$UERANSIM_DIR" \
        "$UE_CONFIG" \
        "$TUN_IF" \
        "$PING_TARGET" \
        "$WAIT_SECONDS" <<'IN_CONTAINER'

set -e

UERANSIM_DIR="$1"
UE_CONFIG="$2"
TUN_IF="$3"
PING_TARGET="$4"
WAIT_SECONDS="$5"

LOG_DIR="/tmp/ueransim-control"
UE_LOG="$LOG_DIR/nr-ue.log"

mkdir -p "$LOG_DIR"

get_tun_ip() {
    if command -v ip >/dev/null 2>&1; then
        ip -4 -o addr show dev "$TUN_IF" 2>/dev/null \
            | awk '{split($4, a, "/"); print a[1]; exit}'
        return
    fi

    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig "$TUN_IF" 2>/dev/null \
            | awk '
                /inet / {
                    for (i = 1; i <= NF; i++) {
                        if ($i == "inet") {
                            print $(i + 1)
                            exit
                        }
                        if ($i ~ /^addr:/) {
                            sub(/^addr:/, "", $i)
                            print $i
                            exit
                        }
                    }
                }
            '
        return
    fi
}

echo "Stopping existing ping process, if any..."
pkill -f "ping .*${PING_TARGET}" 2>/dev/null || true
sleep 1
pkill -9 -f "ping .*${PING_TARGET}" 2>/dev/null || true

echo "Stopping existing nr-ue process, if any..."
pkill -f "nr-ue" 2>/dev/null || true
sleep 1
pkill -9 -f "nr-ue" 2>/dev/null || true

if [ ! -d "$UERANSIM_DIR" ]; then
    echo "ERROR: UERANSIM directory not found: $UERANSIM_DIR"
    exit 1
fi

if [ ! -f "$UE_CONFIG" ]; then
    echo "ERROR: UE config not found: $UE_CONFIG"
    exit 1
fi

cd "$UERANSIM_DIR"

echo "Starting nr-ue in background..."
: > "$UE_LOG"

nohup nr-ue -c "$UE_CONFIG" > "$UE_LOG" 2>&1 &
UE_PID="$!"

echo "nr-ue PID: $UE_PID"
echo "Waiting for TUN interface $TUN_IF to get an IP..."

UE_IP=""

for i in $(seq 1 "$WAIT_SECONDS"); do
    UE_IP="$(get_tun_ip || true)"

    if [ -n "$UE_IP" ]; then
        echo "UE is connected."
        echo "TUN interface: $TUN_IF"
        echo "UE IP: $UE_IP"
        echo
        echo "Starting ping. Press Ctrl+C to stop ping."
        echo

        ping -I "$UE_IP" "$PING_TARGET"
        exit $?
    fi

    if ! kill -0 "$UE_PID" 2>/dev/null; then
        echo "ERROR: nr-ue exited before TUN interface became ready."
        echo
        tail -50 "$UE_LOG" || true
        exit 1
    fi

    sleep 1
done

echo "ERROR: UE did not get a TUN IP within ${WAIT_SECONDS} seconds."
echo
tail -50 "$UE_LOG" || true
exit 1

IN_CONTAINER
}

###############################################################################
# Clean all processes
###############################################################################

clean_all() {
    log "Cleaning ping, UE, and GNodeB processes..."

    run_inside_test_container "$PING_TARGET" <<'IN_CONTAINER'

set -e

PING_TARGET="$1"

echo "Stopping ping..."
pkill -f "ping .*${PING_TARGET}" 2>/dev/null || true
sleep 1
pkill -9 -f "ping .*${PING_TARGET}" 2>/dev/null || true

echo "Stopping nr-ue..."
pkill -f "nr-ue" 2>/dev/null || true
sleep 1
pkill -9 -f "nr-ue" 2>/dev/null || true

echo "Stopping nr-gnb..."
pkill -f "nr-gnb" 2>/dev/null || true
sleep 1
pkill -9 -f "nr-gnb" 2>/dev/null || true

echo "Cleanup complete."

IN_CONTAINER
}

###############################################################################
# Main script
###############################################################################

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
fi

if [ $# -ne 2 ]; then
    usage
    exit 1
fi

NAMESPACE="$1"
ACTION="$2"

command -v kubectl >/dev/null 2>&1 || die "kubectl command not found"

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 \
    || die "Namespace not found: $NAMESPACE"

POD_NAME="$(find_test_pod)"

if [ -z "$POD_NAME" ]; then
    echo "ERROR: Could not find a running pod matching: $TEST_POD_PATTERN"
    echo
    kubectl get pods -n "$NAMESPACE"
    exit 1
fi

log "Namespace: $NAMESPACE"
log "Pod:       $POD_NAME"
log "Container: $TEST_CONTAINER"

case "$ACTION" in
    --configure)
        configure
        ;;
    --startgnb)
        start_gnb
        ;;
    --startue)
        start_ue
        ;;
    --cleanall)
        clean_all
        ;;
    --all)
        configure
        start_gnb
        start_ue
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo "ERROR: Unknown option: $ACTION"
        echo
        usage
        exit 1
        ;;
esac
