#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/steam:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-startup-steam}"
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-30}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam}"
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
    log_error "Image ${IMAGE_NAME} not found. Pull or build the image first."
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

log_info "Checking for startup script at /opt/gow/startup.sh..."
STARTUP_SCRIPT_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /opt/gow/startup.sh && echo "yes" || echo "no")
if [[ "${STARTUP_SCRIPT_EXISTS}" != "yes" ]]; then
    log_error "Startup script not found at /opt/gow/startup.sh"
    echo "RESULT: FAILED (startup script missing)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Startup script found"
log_info "Checking startup script permissions..."
SCRIPT_PERMS=$(docker exec "${CONTAINER_NAME}" stat -c "%a" /opt/gow/startup.sh)
log_info "Startup script permissions: ${SCRIPT_PERMS}"

if [[ $((SCRIPT_PERMS & 1)) -eq 0 ]] && [[ $((SCRIPT_PERMS & 10)) -eq 0 ]] && [[ $((SCRIPT_PERMS & 100)) -eq 0 ]]; then
    log_error "Startup script is not executable"
    echo "RESULT: FAILED (startup script not executable)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Checking startup script shebang..."
SHEBANG=$(docker exec "${CONTAINER_NAME}" head -1 /opt/gow/startup.sh)

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

log_info "Checking for entrypoint script..."
ENTRYPOINT_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /opt/gow/entrypoint.sh && echo "yes" || echo "no")
ENTRYPOINT_EXEC=$(docker exec "${CONTAINER_NAME}" test -x /opt/gow/entrypoint.sh && echo "yes" || echo "no")

log_info "Checking for launch-comp script..."
LAUNCH_COMP_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /opt/gow/launch-comp.sh && echo "yes" || echo "no")
LAUNCH_COMP_EXEC=$(docker exec "${CONTAINER_NAME}" test -x /opt/gow/launch-comp.sh && echo "yes" || echo "no")

log_info "Checking for system-services script..."
SYSTEM_SERVICES_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /etc/cont-init.d/system-services.sh && echo "yes" || echo "no")
SYSTEM_SERVICES_EXEC=$(docker exec "${CONTAINER_NAME}" test -x /etc/cont-init.d/system-services.sh && echo "yes" || echo "no")

log_info "Checking for NVIDIA init script..."
NVIDIA_INIT_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /etc/cont-init.d/10-nvidia.sh && echo "yes" || echo "no")
NVIDIA_INIT_EXEC=$(docker exec "${CONTAINER_NAME}" test -x /etc/cont-init.d/10-nvidia.sh && echo "yes" || echo "no")
NVIDIA_VULKAN_ICD_COPY=$(docker exec "${CONTAINER_NAME}" grep -cF '/usr/share/vulkan/icd.d/' /etc/cont-init.d/10-nvidia.sh 2>/dev/null || echo "0")
NVIDIA_LD_LIBRARY_PATH=$(docker exec "${CONTAINER_NAME}" grep -cF 'LD_LIBRARY_PATH' /etc/cont-init.d/10-nvidia.sh 2>/dev/null || echo "0")
NVIDIA_VK_DRIVER_FILES=$(docker exec "${CONTAINER_NAME}" grep -cF 'VK_DRIVER_FILES' /etc/cont-init.d/10-nvidia.sh 2>/dev/null || echo "0")
NVIDIA_GBM_COPY=$(docker exec "${CONTAINER_NAME}" grep -cF '/lib/gbm' /etc/cont-init.d/10-nvidia.sh 2>/dev/null || echo "0")

{
    echo "=== GoW Scripts ==="
    echo "/opt/gow/entrypoint.sh: ${ENTRYPOINT_EXISTS} (executable: ${ENTRYPOINT_EXEC})"
    echo "/opt/gow/launch-comp.sh: ${LAUNCH_COMP_EXISTS} (executable: ${LAUNCH_COMP_EXEC})"
    echo "/etc/cont-init.d/system-services.sh: ${SYSTEM_SERVICES_EXISTS} (executable: ${SYSTEM_SERVICES_EXEC})"
    echo "/etc/cont-init.d/10-nvidia.sh: ${NVIDIA_INIT_EXISTS} (executable: ${NVIDIA_INIT_EXEC})"
    echo "NVIDIA Vulkan ICD copy pattern: ${NVIDIA_VULKAN_ICD_COPY}"
    echo "NVIDIA LD_LIBRARY_PATH pattern: ${NVIDIA_LD_LIBRARY_PATH}"
    echo "NVIDIA VK_DRIVER_FILES pattern: ${NVIDIA_VK_DRIVER_FILES}"
    echo "NVIDIA GBM copy pattern: ${NVIDIA_GBM_COPY}"
} >> "${EVIDENCE_FILE}"

if [[ "${ENTRYPOINT_EXISTS}" != "yes" ]]; then
    log_error "Entrypoint script not found at /opt/gow/entrypoint.sh"
    echo "RESULT: FAILED (entrypoint missing)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${ENTRYPOINT_EXEC}" != "yes" ]]; then
    log_error "Entrypoint script is not executable"
    echo "RESULT: FAILED (entrypoint not executable)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${LAUNCH_COMP_EXISTS}" != "yes" ]]; then
    log_error "Launch-comp script not found at /opt/gow/launch-comp.sh"
    echo "RESULT: FAILED (launch-comp missing)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${LAUNCH_COMP_EXEC}" != "yes" ]]; then
    log_error "Launch-comp script is not executable"
    echo "RESULT: FAILED (launch-comp not executable)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${SYSTEM_SERVICES_EXISTS}" != "yes" ]]; then
    log_error "System-services script not found at /etc/cont-init.d/system-services.sh"
    echo "RESULT: FAILED (system-services missing)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${SYSTEM_SERVICES_EXEC}" != "yes" ]]; then
    log_error "System-services script is not executable"
    echo "RESULT: FAILED (system-services not executable)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${NVIDIA_INIT_EXISTS}" != "yes" || "${NVIDIA_INIT_EXEC}" != "yes" ]]; then
    log_error "NVIDIA init script not found or not executable at /etc/cont-init.d/10-nvidia.sh"
    echo "RESULT: FAILED (nvidia init missing)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${NVIDIA_VULKAN_ICD_COPY}" -lt 1 ]]; then
    log_error "NVIDIA init script does not copy Vulkan ICDs to /usr/share/vulkan/icd.d/"
    echo "RESULT: FAILED (nvidia vulkan icd copy)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "All GoW scripts found and executable"

log_info "Checking runtime user convention in entrypoint..."
RUNTIME_USER=$(docker exec "${CONTAINER_NAME}" awk -F'"' '/^UNAME=/{print $2}' /opt/gow/entrypoint.sh)

{
    echo "=== Runtime User ==="
    echo "Entrypoint UNAME: ${RUNTIME_USER}"
} >> "${EVIDENCE_FILE}"

if [[ "${RUNTIME_USER}" != "retro" ]]; then
    log_error "Entrypoint runtime user is ${RUNTIME_USER}, expected retro"
    echo "RESULT: FAILED (runtime user mismatch)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Checking XDG_RUNTIME_DIR handling in entrypoint..."
XDG_FALLBACK_COUNT=$(docker exec "${CONTAINER_NAME}" grep -F -c 'XDG_RUNTIME_DIR:-/tmp/.X11-unix' /opt/gow/entrypoint.sh || true)
XDG_CHOWN_RECURSIVE_COUNT=$(docker exec "${CONTAINER_NAME}" grep -F -c 'chown -R "${PUID}:${PGID}" "${XDG_RUNTIME_DIR}"' /opt/gow/entrypoint.sh || true)

{
    echo "=== XDG_RUNTIME_DIR Handling ==="
    echo "Entrypoint fallback pattern count: ${XDG_FALLBACK_COUNT}"
    echo "Entrypoint recursive chown pattern count: ${XDG_CHOWN_RECURSIVE_COUNT}"
} >> "${EVIDENCE_FILE}"

if [[ "${XDG_FALLBACK_COUNT}" -lt 1 ]]; then
    log_error "Entrypoint does not contain XDG_RUNTIME_DIR fallback pattern"
    echo "RESULT: FAILED (XDG_RUNTIME_DIR fallback)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${XDG_CHOWN_RECURSIVE_COUNT}" -lt 1 ]]; then
    log_error "Entrypoint does not recursively chown XDG_RUNTIME_DIR"
    echo "RESULT: FAILED (XDG_RUNTIME_DIR ownership handling)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Checking SteamOS stub scripts..."

STEAMOS_UPDATE_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /usr/bin/steamos-update && echo "yes" || echo "no")
STEAMOS_UPDATE_EXEC=$(docker exec "${CONTAINER_NAME}" test -x /usr/bin/steamos-update && echo "yes" || echo "no")

STEAMOS_SESSION_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /usr/bin/steamos-session-select && echo "yes" || echo "no")
STEAMOS_SESSION_EXEC=$(docker exec "${CONTAINER_NAME}" test -x /usr/bin/steamos-session-select && echo "yes" || echo "no")

JUPITER_BIOS_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /usr/bin/jupiter-biosupdate && echo "yes" || echo "no")
JUPITER_BIOS_EXEC=$(docker exec "${CONTAINER_NAME}" test -x /usr/bin/jupiter-biosupdate && echo "yes" || echo "no")

STEAMOS_DBUS_WATCHDOG_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /usr/local/bin/steamos-dbus-watchdog.sh && echo "yes" || echo "no")
STEAMOS_DBUS_WATCHDOG_EXEC=$(docker exec "${CONTAINER_NAME}" test -x /usr/local/bin/steamos-dbus-watchdog.sh && echo "yes" || echo "no")

{
    echo "=== SteamOS Stubs ==="
    echo "/usr/bin/steamos-update: ${STEAMOS_UPDATE_EXISTS} (executable: ${STEAMOS_UPDATE_EXEC})"
    echo "/usr/bin/steamos-session-select: ${STEAMOS_SESSION_EXISTS} (executable: ${STEAMOS_SESSION_EXEC})"
    echo "/usr/bin/jupiter-biosupdate: ${JUPITER_BIOS_EXISTS} (executable: ${JUPITER_BIOS_EXEC})"
    echo "/usr/local/bin/steamos-dbus-watchdog.sh: ${STEAMOS_DBUS_WATCHDOG_EXISTS} (executable: ${STEAMOS_DBUS_WATCHDOG_EXEC})"
} >> "${EVIDENCE_FILE}"

if [[ "${STEAMOS_UPDATE_EXISTS}" != "yes" || "${STEAMOS_UPDATE_EXEC}" != "yes" ]]; then
    log_error "steamos-update not found or not executable"
    echo "RESULT: FAILED (steamos-update)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${STEAMOS_SESSION_EXISTS}" != "yes" || "${STEAMOS_SESSION_EXEC}" != "yes" ]]; then
    log_error "steamos-session-select not found or not executable"
    echo "RESULT: FAILED (steamos-session-select)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${JUPITER_BIOS_EXISTS}" != "yes" || "${JUPITER_BIOS_EXEC}" != "yes" ]]; then
    log_error "jupiter-biosupdate not found or not executable"
    echo "RESULT: FAILED (jupiter-biosupdate)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${STEAMOS_DBUS_WATCHDOG_EXISTS}" != "yes" || "${STEAMOS_DBUS_WATCHDOG_EXEC}" != "yes" ]]; then
    log_error "steamos-dbus-watchdog.sh not found or not executable"
    echo "RESULT: FAILED (steamos-dbus-watchdog.sh)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "All SteamOS stubs found and executable"

log_info "Checking patched bubblewrap..."
BWRAP_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /usr/bin/bwrap && echo "yes" || echo "no")
BWRAP_EXEC=$(docker exec "${CONTAINER_NAME}" test -x /usr/bin/bwrap && echo "yes" || echo "no")

{
    echo "=== Patched Bubblewrap ==="
    echo "/usr/bin/bwrap: ${BWRAP_EXISTS} (executable: ${BWRAP_EXEC})"
} >> "${EVIDENCE_FILE}"

if [[ "${BWRAP_EXISTS}" != "yes" ]]; then
    log_error "bwrap not found at /usr/bin/bwrap"
    echo "RESULT: FAILED (bwrap missing)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ "${BWRAP_EXEC}" != "yes" ]]; then
    log_error "bwrap is not executable"
    echo "RESULT: FAILED (bwrap not executable)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Patched bubblewrap found and executable"

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"

log_info "All startup tests passed"
echo ""
echo "=== TEST PASSED ==="
exit 0
