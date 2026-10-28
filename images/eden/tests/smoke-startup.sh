#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/eden:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-startup}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/eden}"
EVIDENCE_FILE="${EVIDENCE_DIR}/startup.txt"
STUB_DIR=""

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

mkdir -p "${EVIDENCE_DIR}"

{
    echo "=== Smoke Test: Container Startup ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Image: ${IMAGE_NAME}"
    echo "Container: ${CONTAINER_NAME}"
    echo ""
} > "${EVIDENCE_FILE}"

cleanup() {
    log_info "Cleaning up container ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    if [[ -n "${STUB_DIR}" ]]; then
        rm -rf "${STUB_DIR}"
    fi
}
trap cleanup EXIT

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    log_error "Image ${IMAGE_NAME} not found. Run the build first."
    echo "ERROR: Image not found" >> "${EVIDENCE_FILE}"
    exit 1
fi

STUB_DIR="$(mktemp -d "${EVIDENCE_DIR}/startup-stub.XXXXXX")"
LAUNCH_STUB_PATH="${STUB_DIR}/launch-gamescope.sh"
SENTINEL_PATH="${STUB_DIR}/invoked"
FAKE_NVIDIA_ICD="${STUB_DIR}/nvidia_icd.json"
RUN_LOG="${STUB_DIR}/docker-run.log"

cat > "${LAUNCH_STUB_PATH}" <<'EOF'
#!/bin/bash
set -euo pipefail
{
    echo "launch-gamescope startup stub invoked"
    echo "argv: $*"
    echo "XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-unset}"
    echo "DISABLE_AUTO_UPDATES: ${DISABLE_AUTO_UPDATES:-unset}"
    echo "SHARUN_ALLOW_SYS_VKICD: ${SHARUN_ALLOW_SYS_VKICD:-unset}"
} >> "${STARTUP_SENTINEL:?}"
EOF
chmod +x "${LAUNCH_STUB_PATH}"

printf '%s\n' '{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.4.0"}}' > "${FAKE_NVIDIA_ICD}"

run_container() {
    local mount_args=("$@")

    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

    docker run \
        --name "${CONTAINER_NAME}" \
        -e PUID=0 \
        -e STARTUP_SENTINEL=/tmp/startup-smoke/invoked \
        -v "${LAUNCH_STUB_PATH}:/opt/gow/launch-gamescope.sh:ro" \
        -v "${STUB_DIR}:/tmp/startup-smoke" \
        "${mount_args[@]}" \
        "${IMAGE_NAME}" > "${RUN_LOG}" 2>&1
    echo $?
}

log_info "Exercising inherited entrypoint and /opt/gow/startup.sh without an NVIDIA ICD..."
set +e
exit_code="$(run_container)"
set -e

{
    echo "=== docker run output (no nvidia icd) ==="
    cat "${RUN_LOG}"
    echo "=== startup stub output ==="
    cat "${SENTINEL_PATH}" 2>/dev/null || echo "startup stub was not invoked"
} >> "${EVIDENCE_FILE}"

if [[ "${exit_code}" -ne 0 ]]; then
    log_error "Container startup path failed (exit ${exit_code})"
    echo "RESULT: FAILED (startup path)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ ! -f "${SENTINEL_PATH}" ]]; then
    log_error "Startup script did not invoke launch-gamescope"
    echo "RESULT: FAILED (gamescope helper not invoked)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if ! grep -q "argv: /opt/eden/AppRun" "${SENTINEL_PATH}"; then
    log_error "Startup script did not launch Eden through gamescope"
    echo "RESULT: FAILED (gamescope helper argv)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if ! grep -q "XDG_RUNTIME_DIR: /run/user/0" "${SENTINEL_PATH}"; then
    log_error "XDG_RUNTIME_DIR was not set for the startup path"
    echo "RESULT: FAILED (XDG_RUNTIME_DIR)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if ! grep -q "DISABLE_AUTO_UPDATES: 1" "${SENTINEL_PATH}"; then
    log_error "AppImage self-updater was not disabled"
    echo "RESULT: FAILED (self-updater)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if grep -q "SHARUN_ALLOW_SYS_VKICD: 1" "${SENTINEL_PATH}"; then
    log_error "System Vulkan ICDs enabled on a host without an NVIDIA ICD"
    echo "RESULT: FAILED (nvidia icd detection)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Exercising startup with an NVIDIA ICD present..."
rm -f "${SENTINEL_PATH}"
set +e
exit_code="$(run_container -v "${FAKE_NVIDIA_ICD}:/usr/share/vulkan/icd.d/nvidia_icd.json:ro")"
set -e

{
    echo "=== docker run output (nvidia icd present) ==="
    cat "${RUN_LOG}"
    echo "=== startup stub output ==="
    cat "${SENTINEL_PATH}" 2>/dev/null || echo "startup stub was not invoked"
} >> "${EVIDENCE_FILE}"

if [[ "${exit_code}" -ne 0 ]]; then
    log_error "Container startup path failed with an NVIDIA ICD (exit ${exit_code})"
    echo "RESULT: FAILED (startup path with nvidia icd)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if ! grep -q "SHARUN_ALLOW_SYS_VKICD: 1" "${SENTINEL_PATH}"; then
    log_error "System Vulkan ICDs were not enabled despite an NVIDIA ICD"
    echo "RESULT: FAILED (nvidia icd handling)" >> "${EVIDENCE_FILE}"
    exit 1
fi

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "Startup path test passed"
echo ""
echo "=== TEST PASSED ==="
exit 0
