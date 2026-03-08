#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/prism-offline:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-startup}"
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-30}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../test-results/prism-offline}"
EVIDENCE_FILE="${EVIDENCE_DIR}/startup.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

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
}
trap cleanup EXIT

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    log_error "Image ${IMAGE_NAME} not found. Run smoke-build.sh first."
    echo "ERROR: Image not found" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Starting container with sleep command..."
set +e
docker run -d --entrypoint "" --name "${CONTAINER_NAME}" "${IMAGE_NAME}" sleep infinity
RUN_EXIT_CODE=$?
set -e

if [[ ${RUN_EXIT_CODE} -ne 0 ]]; then
    log_error "Failed to start container"
    echo "RESULT: FAILED (container start)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Waiting for container to be running..."
sleep 2

CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "${CONTAINER_NAME}")
if [[ "${CONTAINER_STATUS}" != "running" ]]; then
    log_error "Container is not running. Status: ${CONTAINER_STATUS}"
    echo "RESULT: FAILED (container not running)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Container is running"

log_info "Checking for startup script at /opt/gow/startup-app.sh..."
STARTUP_SCRIPT_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /opt/gow/startup-app.sh && echo "yes" || echo "no")
if [[ "${STARTUP_SCRIPT_EXISTS}" != "yes" ]]; then
    log_error "Startup script not found at /opt/gow/startup-app.sh"
    echo "RESULT: FAILED (startup script missing)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Startup script found"
log_info "Checking startup script permissions..."
SCRIPT_PERMS=$(docker exec "${CONTAINER_NAME}" stat -c "%a" /opt/gow/startup-app.sh)
log_info "Startup script permissions: ${SCRIPT_PERMS}"

if [[ $((SCRIPT_PERMS & 1)) -eq 0 ]] && [[ $((SCRIPT_PERMS & 10)) -eq 0 ]] && [[ $((SCRIPT_PERMS & 100)) -eq 0 ]]; then
    log_error "Startup script is not executable"
    echo "RESULT: FAILED (startup script not executable)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Checking startup script shebang..."
SHEBANG=$(docker exec "${CONTAINER_NAME}" head -1 /opt/gow/startup-app.sh)
{
    echo "=== Startup Script Info ==="
    echo "Permissions: ${SCRIPT_PERMS}"
    echo "Shebang: ${SHEBANG}"
} >> "${EVIDENCE_FILE}"

if [[ ! "${SHEBANG}" =~ ^#!.*bash ]]; then
    log_error "Startup script does not have bash shebang: ${SHEBANG}"
    echo "RESULT: FAILED (invalid shebang)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Checking for GoW utilities..."
GOW_UTILS_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /opt/gow/bash-lib/utils.sh && echo "yes" || echo "no")
LAUNCH_COMP_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /opt/gow/launch-comp.sh && echo "yes" || echo "no")
{
    echo "=== GoW Utilities ==="
    echo "utils.sh: ${GOW_UTILS_EXISTS}"
    echo "launch-comp.sh: ${LAUNCH_COMP_EXISTS}"
} >> "${EVIDENCE_FILE}"

if [[ "${GOW_UTILS_EXISTS}" != "yes" ]]; then
    log_warn "GoW utils.sh not found (may be expected in base image)"
fi

if [[ "${LAUNCH_COMP_EXISTS}" != "yes" ]]; then
    log_warn "GoW launch-comp.sh not found (may be expected in base image)"
fi

log_info "Checking XDG_RUNTIME_DIR environment variable..."
XDG_RUNTIME=$(docker exec "${CONTAINER_NAME}" printenv XDG_RUNTIME_DIR)
{
    echo "=== Environment ==="
    echo "XDG_RUNTIME_DIR: ${XDG_RUNTIME}"
} >> "${EVIDENCE_FILE}"

if [[ "${XDG_RUNTIME}" != "/tmp/.X11-unix" ]]; then
    log_error "XDG_RUNTIME_DIR is not set correctly: ${XDG_RUNTIME}"
    echo "RESULT: FAILED (XDG_RUNTIME_DIR)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Checking prismlauncher target path..."
PRISM_PATH=$(docker exec "${CONTAINER_NAME}" readlink -f /usr/local/bin/prismlauncher)
{
    echo "=== Prism Launcher Path ==="
    echo "Path: ${PRISM_PATH}"
} >> "${EVIDENCE_FILE}"

if [[ "${PRISM_PATH}" != "/opt/prismlauncher/squashfs-root/AppRun" ]]; then
    log_error "prismlauncher does not point to extracted AppRun: ${PRISM_PATH}"
    echo "RESULT: FAILED (prismlauncher path)" >> "${EVIDENCE_FILE}"
    exit 1
fi

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"

log_info "All startup tests passed"
echo ""
echo "=== TEST PASSED ==="
exit 0
