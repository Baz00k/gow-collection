#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/baz00k/gow-collection/wivrn:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-startup-wivrn}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/wivrn}"
EVIDENCE_FILE="${EVIDENCE_DIR}/startup.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

mkdir -p "${EVIDENCE_DIR}"
{
    echo "=== Smoke Test: WiVRn Startup ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Image: ${IMAGE_NAME}"
    echo "Container: ${CONTAINER_NAME}"
    echo ""
} > "${EVIDENCE_FILE}"

# shellcheck disable=SC2329 # Invoked via trap.
cleanup() {
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
}
trap cleanup EXIT

fail() {
    log_error "$1"
    echo "RESULT: FAILED ($1)" >> "${EVIDENCE_FILE}"
    exit 1
}

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    fail "image not found"
fi

log_info "Starting container..."
docker run -d --entrypoint "" --name "${CONTAINER_NAME}" "${IMAGE_NAME}" sleep infinity >/dev/null
sleep 2

if [[ "$(docker inspect --format='{{.State.Status}}' "${CONTAINER_NAME}")" != "running" ]]; then
    fail "container not running"
fi

REQUIRED_EXEC=(
    /opt/gow/startup.sh
    /opt/gow/wivrn-session.sh
    /opt/gow/wivrn-config.sh
    /etc/cont-init.d/45-system-services.sh
    /opt/gow/entrypoint.sh
    /opt/gow/launch-gamescope.sh
    /usr/bin/steam
    /usr/bin/gamescope
    /usr/bin/wivrn-server
    /usr/bin/wivrnctl
    /usr/bin/pipewire
    /usr/bin/pipewire-pulse
    /usr/bin/wireplumber
    /usr/bin/dbus-daemon
    /usr/bin/dbus-run-session
    /usr/bin/vulkaninfo
    /usr/bin/xwininfo
)

for f in "${REQUIRED_EXEC[@]}"; do
    if ! docker exec "${CONTAINER_NAME}" test -x "$f"; then
        fail "missing or not executable ${f}"
    fi
    echo "${f}: ok" >> "${EVIDENCE_FILE}"
done

if ! docker exec "${CONTAINER_NAME}" sh -c 'command -v avahi-daemon' >/dev/null; then
    fail "avahi-daemon not found on PATH"
fi
echo "avahi-daemon: ok" >> "${EVIDENCE_FILE}"

if ! docker exec "${CONTAINER_NAME}" test -s /etc/wivrn/config.json; then
    fail "WiVRn system config missing"
fi
echo "/etc/wivrn/config.json: ok" >> "${EVIDENCE_FILE}"

if ! docker exec "${CONTAINER_NAME}" /usr/bin/python3 -c 'import json; json.load(open("/etc/wivrn/config.json"))'; then
    fail "WiVRn system config is not valid JSON"
fi
echo "/etc/wivrn/config.json valid JSON: ok" >> "${EVIDENCE_FILE}"

if ! docker exec "${CONTAINER_NAME}" sh -c 'ls /usr/share/openxr/1 2>/dev/null | grep -qi wivrn'; then
    fail "no WiVRn OpenXR runtime manifest in /usr/share/openxr/1"
fi
echo "OpenXR runtime manifest: ok" >> "${EVIDENCE_FILE}"

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "WiVRn startup smoke test passed"
exit 0
