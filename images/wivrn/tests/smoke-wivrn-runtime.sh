#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/baz00k/gow-collection/wivrn:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-wivrn-runtime}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/wivrn}"
EVIDENCE_FILE="${EVIDENCE_DIR}/wivrn-runtime.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
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
sleep 2

if [[ "$(docker inspect --format='{{.State.Status}}' "${CONTAINER_NAME}")" != "running" ]]; then
    fail "container not running"
fi

log_info "Checking OpenXR runtime manifest..."
MANIFESTS="$(docker exec "${CONTAINER_NAME}" sh -c 'find /usr/share/openxr -iname "*wivrn*.json" 2>/dev/null' || true)"
if [[ -z "${MANIFESTS}" ]]; then
    fail "no WiVRn OpenXR manifest found under /usr/share/openxr"
fi
echo "manifests:" >> "${EVIDENCE_FILE}"
echo "${MANIFESTS}" >> "${EVIDENCE_FILE}"

while IFS= read -r manifest; do
    [[ -z "${manifest}" ]] && continue
    if ! docker exec "${CONTAINER_NAME}" /usr/bin/python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "${manifest}"; then
        fail "manifest is not valid JSON: ${manifest}"
    fi
    LIBRARY="$(docker exec "${CONTAINER_NAME}" /usr/bin/python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["runtime"]["library_path"])' "${manifest}" || true)"
    if [[ -z "${LIBRARY}" ]]; then
        fail "manifest has no runtime.library_path: ${manifest}"
    fi
    echo "library_path: ${LIBRARY}" >> "${EVIDENCE_FILE}"
    MANIFEST_DIR="$(dirname "${manifest}")"
    if ! docker exec "${CONTAINER_NAME}" sh -c \
        "test -f '${LIBRARY}' || test -f '${MANIFEST_DIR}/${LIBRARY}' || test -f '/usr/lib64/${LIBRARY}' || test -f '/usr/lib64/wivrn/${LIBRARY}'"; then
        fail "OpenXR runtime library missing: ${LIBRARY}"
    fi
    echo "runtime library resolves: ok" >> "${EVIDENCE_FILE}"
done <<< "${MANIFESTS}"

log_info "Checking OpenComposite compat library layout..."
# The compat path must resolve bin/linux64/vrclient.so underneath it: WiVRn
# (active_runtime.cpp) and the OpenVR loader both append that suffix. A
# wrong level (e.g. Fedora's /usr/lib64/opencomposite without /runtime)
# silently drops games to desktop mode — no HMD image, no tracking.
EXPECTED_COMPAT="$(grep '^WIVRN_OPENVR_COMPAT_PATH=' "${SCRIPT_DIR}/../build/overlay/opt/gow/wivrn-config.sh" | head -1 | grep -o '/[^"}]*' || true)"
if [[ -z "${EXPECTED_COMPAT}" ]]; then
    EXPECTED_COMPAT="/usr/lib64/opencomposite/runtime"
fi
echo "expected compat path: ${EXPECTED_COMPAT}" >> "${EVIDENCE_FILE}"
if ! docker exec "${CONTAINER_NAME}" test -f "${EXPECTED_COMPAT}/bin/linux64/vrclient.so"; then
    fail "OpenVR compat library missing: ${EXPECTED_COMPAT}/bin/linux64/vrclient.so not found in image"
fi
echo "compat vrclient.so resolves: ok" >> "${EVIDENCE_FILE}"

log_info "Checking pinned xrizer supports IVRSystem_026..."
if ! docker exec "${CONTAINER_NAME}" sh -c \
    'test -f /usr/lib64/xrizer/runtime/bin/linux64/vrclient.so && grep -aFq IVRSystem_026 /usr/lib64/xrizer/runtime/bin/linux64/vrclient.so'; then
    fail "xrizer is missing or does not contain IVRSystem_026"
fi
echo "xrizer IVRSystem_026: ok" >> "${EVIDENCE_FILE}"

log_info "Checking wivrn-server..."
if ! docker exec "${CONTAINER_NAME}" wivrn-server --help >> "${EVIDENCE_FILE}" 2>&1; then
    fail "wivrn-server --help failed"
fi
echo "wivrn-server --help: ok" >> "${EVIDENCE_FILE}"

EXPECTED_VERSION="$(grep '^WIVRN_VERSION=' "${SCRIPT_DIR}/../build/pins.env" | head -1 | cut -d= -f2- || true)"
if [[ -z "${EXPECTED_VERSION}" ]]; then
    fail "WIVRN_VERSION pin missing"
fi
SERVER_VERSION="$(docker exec "${CONTAINER_NAME}" wivrn-server --version 2>&1 || true)"
echo "wivrn-server version output: ${SERVER_VERSION}" >> "${EVIDENCE_FILE}"
if ! grep -qF "${EXPECTED_VERSION}" <<< "${SERVER_VERSION}"; then
    fail "wivrn-server version does not match pinned WIVRN_VERSION=${EXPECTED_VERSION} (client and server versions must match)"
fi
echo "wivrn-server version ${EXPECTED_VERSION}: ok" >> "${EVIDENCE_FILE}"

log_info "Checking OpenComposite compat detection..."
if ! docker exec "${CONTAINER_NAME}" sh -c 'mkdir -p /run/dbus && dbus-daemon --system --fork --nosyslog'; then
    fail "could not start system D-Bus for compat probe"
fi
if ! docker exec -e HOME=/tmp/compat-test "${CONTAINER_NAME}" /opt/gow/wivrn-config.sh >> "${EVIDENCE_FILE}" 2>&1; then
    fail "wivrn-config.sh failed for compat probe"
fi
COMPAT_LOG="$(docker exec -e HOME=/tmp/compat-test -e XDG_RUNTIME_DIR=/tmp/wxdg "${CONTAINER_NAME}" \
    sh -c 'dbus-run-session -- timeout 10 wivrn-server 2>&1' || true)"
echo "${COMPAT_LOG}" >> "${EVIDENCE_FILE}"
if ! grep -qF 'VR_OVERRIDE=/run/host/usr/lib64/opencomposite' <<< "${COMPAT_LOG}"; then
    fail "wivrn-server did not pick up OpenComposite from openvr-compat-path"
fi
echo "OpenComposite compat detected: ok" >> "${EVIDENCE_FILE}"

log_info "Checking wivrnctl..."
if ! docker exec "${CONTAINER_NAME}" wivrnctl --help >> "${EVIDENCE_FILE}" 2>&1; then
    fail "wivrnctl --help failed"
fi
echo "wivrnctl --help: ok" >> "${EVIDENCE_FILE}"

log_info "Checking Vulkan loader (software rendering is acceptable)..."
if docker exec "${CONTAINER_NAME}" vulkaninfo --summary >> "${EVIDENCE_FILE}" 2>&1; then
    echo "vulkaninfo --summary: ok" >> "${EVIDENCE_FILE}"
else
    log_warn "vulkaninfo --summary failed; GPU-dependent, not fatal"
    echo "vulkaninfo --summary: WARN (see output above)" >> "${EVIDENCE_FILE}"
fi

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "WiVRn runtime smoke test passed"
exit 0
