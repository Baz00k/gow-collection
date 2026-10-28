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
KEYS_DIR="${STUB_DIR}/keys"
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
    echo "keys: $(ls "${HOME}/.local/share/eden/keys" 2>/dev/null | tr '\n' ' ')"
} >> "${STARTUP_SENTINEL:?}"
EOF
chmod +x "${LAUNCH_STUB_PATH}"

printf '%s\n' '{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.4.0"}}' > "${FAKE_NVIDIA_ICD}"
mkdir -p "${KEYS_DIR}"
printf 'fake-key-material\n' > "${KEYS_DIR}/prod.keys"
printf 'fake-title-key-material\n' > "${KEYS_DIR}/title.keys"

run_container() {
    local puid="$1"
    shift

    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

    docker run \
        --name "${CONTAINER_NAME}" \
        -e PUID="${puid}" \
        -e STARTUP_SENTINEL=/tmp/startup-smoke/invoked \
        -v "${LAUNCH_STUB_PATH}:/opt/gow/launch-gamescope.sh:ro" \
        -v "${STUB_DIR}:/tmp/startup-smoke" \
        "$@" \
        "${IMAGE_NAME}" > "${RUN_LOG}" 2>&1
    echo $?
}

# capture <case-label> <exit-code>
capture() {
    {
        echo "=== docker run output (${1}) ==="
        cat "${RUN_LOG}"
        echo "=== startup stub output (${1}) ==="
        cat "${SENTINEL_PATH}" 2>/dev/null || echo "startup stub was not invoked"
        echo ""
    } >> "${EVIDENCE_FILE}"
}

fail_case() {
    log_error "$1"
    echo "RESULT: FAILED ($1)" >> "${EVIDENCE_FILE}"
    exit 1
}

log_info "Exercising startup without an NVIDIA ICD..."
set +e
exit_code="$(run_container 0)"
set -e
capture "no nvidia icd" "${exit_code}"

[[ "${exit_code}" -eq 0 ]] || fail_case "startup path (exit ${exit_code})"
[[ -f "${SENTINEL_PATH}" ]] || fail_case "gamescope helper not invoked"
grep -q "argv: /opt/eden/AppRun" "${SENTINEL_PATH}" || fail_case "gamescope helper argv"
grep -q "XDG_RUNTIME_DIR: /run/user/0" "${SENTINEL_PATH}" || fail_case "XDG_RUNTIME_DIR"
grep -q "DISABLE_AUTO_UPDATES: 1" "${SENTINEL_PATH}" || fail_case "self-updater"
if grep -q "SHARUN_ALLOW_SYS_VKICD: 1" "${SENTINEL_PATH}"; then
    fail_case "system Vulkan ICDs enabled without an NVIDIA ICD"
fi

log_info "Exercising startup with an NVIDIA ICD present..."
rm -f "${SENTINEL_PATH}"
set +e
exit_code="$(run_container 0 -v "${FAKE_NVIDIA_ICD}:/usr/share/vulkan/icd.d/nvidia_icd.json:ro")"
set -e
capture "nvidia icd present" "${exit_code}"

[[ "${exit_code}" -eq 0 ]] || fail_case "startup path with nvidia icd (exit ${exit_code})"
grep -q "SHARUN_ALLOW_SYS_VKICD: 1" "${SENTINEL_PATH}" || fail_case "nvidia icd handling"

log_info "Exercising the documented keys mount as the default runtime user..."
rm -f "${SENTINEL_PATH}"
set +e
exit_code="$(run_container 1000 -v "${KEYS_DIR}:/keys:ro")"
set -e
capture "default user with read-only keys mount" "${exit_code}"

[[ "${exit_code}" -eq 0 ]] || fail_case "startup as runtime user with keys mount (exit ${exit_code})"
grep -q "argv: /opt/eden/AppRun" "${SENTINEL_PATH}" || fail_case "gamescope helper argv (keys case)"
grep -q "keys: prod.keys title.keys" "${SENTINEL_PATH}" || fail_case "keys were not installed into the profile"

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "Startup path test passed"
echo ""
echo "=== TEST PASSED ==="
exit 0
