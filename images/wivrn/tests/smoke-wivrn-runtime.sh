#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/baz00k/gow-collection/wivrn:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-wivrn-runtime}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/wivrn}"
EVIDENCE_FILE="${EVIDENCE_DIR}/wivrn-runtime.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

mkdir -p "${EVIDENCE_DIR}"
{
    echo "=== Smoke Test: WiVRn Runtime ==="
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

# Binaries the services test replaces with PATH stubs.
REQUIRED_EXEC=(
    /usr/bin/pipewire
    /usr/bin/pipewire-pulse
    /usr/bin/wireplumber
    /usr/bin/dbus-daemon
    /usr/bin/dbus-run-session
    /usr/bin/steam
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

if ! docker exec "${CONTAINER_NAME}" /usr/bin/python3 -c 'import json; json.load(open("/etc/wivrn/config.json"))'; then
    fail "WiVRn system config is not valid JSON"
fi
echo "/etc/wivrn/config.json valid JSON: ok" >> "${EVIDENCE_FILE}"

log_info "Checking OpenXR runtime manifest..."
MANIFESTS="$(docker exec "${CONTAINER_NAME}" sh -c 'find /usr/share/openxr -iname "*wivrn*.json" 2>/dev/null' || true)"
if [[ -z "${MANIFESTS}" ]]; then
    fail "no WiVRn OpenXR manifest found under /usr/share/openxr"
fi
echo "manifests:" >> "${EVIDENCE_FILE}"
echo "${MANIFESTS}" >> "${EVIDENCE_FILE}"

while IFS= read -r manifest; do
    [[ -z "${manifest}" ]] && continue
    LIBRARY="$(docker exec "${CONTAINER_NAME}" /usr/bin/python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["runtime"]["library_path"])' "${manifest}" || true)"
    if [[ -z "${LIBRARY}" ]]; then
        fail "manifest is not valid JSON or has no runtime.library_path: ${manifest}"
    fi
    echo "library_path: ${LIBRARY}" >> "${EVIDENCE_FILE}"
    MANIFEST_DIR="$(dirname "${manifest}")"
    if ! docker exec "${CONTAINER_NAME}" sh -c \
        "test -f '${LIBRARY}' || test -f '${MANIFEST_DIR}/${LIBRARY}' || test -f '/usr/lib64/${LIBRARY}' || test -f '/usr/lib64/wivrn/${LIBRARY}'"; then
        fail "OpenXR runtime library missing: ${LIBRARY}"
    fi
    echo "runtime library resolves: ok" >> "${EVIDENCE_FILE}"
done <<< "${MANIFESTS}"

# The xrizer checksum and IVRSystem_026, and the wivrn-server version, are
# asserted by the Dockerfile at build time.
log_info "Checking xrizer shared-library dependencies..."
if ! docker exec "${CONTAINER_NAME}" /usr/bin/python3 -c \
    'import ctypes; ctypes.CDLL("/opt/xrizer/bin/linux64/vrclient.so")' >> "${EVIDENCE_FILE}" 2>&1; then
    fail "xrizer library cannot be loaded (missing dependency or incompatible ABI)"
fi
echo "xrizer library loads: ok" >> "${EVIDENCE_FILE}"

log_info "Checking wivrnctl..."
if ! docker exec "${CONTAINER_NAME}" wivrnctl --help >> "${EVIDENCE_FILE}" 2>&1; then
    fail "wivrnctl --help failed"
fi
echo "wivrnctl --help: ok" >> "${EVIDENCE_FILE}"

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "WiVRn runtime smoke test passed"
exit 0
