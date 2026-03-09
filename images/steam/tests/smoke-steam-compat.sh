#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/steam:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-steam-compat-steam}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../test-results/steam}"
EVIDENCE_FILE="${EVIDENCE_DIR}/steam-compat.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    FAILED=1
}

mkdir -p "${EVIDENCE_DIR}"

{
    echo "=== Smoke Test: Steam Compatibility ==="
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
echo "" >> "${EVIDENCE_FILE}"
echo "=== SteamOS Polkit Helpers ===" >> "${EVIDENCE_FILE}"

log_info "Checking SteamOS polkit helpers..."

STEAMOS_POLKIT_UPDATE_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /usr/bin/steamos-polkit-helpers/steamos-update && echo "yes" || echo "no")
JUPITER_POLKIT_BIOS_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /usr/bin/steamos-polkit-helpers/jupiter-biosupdate && echo "yes" || echo "no")

{
    echo "/usr/bin/steamos-polkit-helpers/steamos-update: ${STEAMOS_POLKIT_UPDATE_EXISTS}"
    echo "/usr/bin/steamos-polkit-helpers/jupiter-biosupdate: ${JUPITER_POLKIT_BIOS_EXISTS}"
} >> "${EVIDENCE_FILE}"

if [[ "${STEAMOS_POLKIT_UPDATE_EXISTS}" != "yes" ]]; then
    log_fail "SteamOS polkit helper: steamos-update not found"
    echo "[FAIL] SteamOS polkit helper: steamos-update not found" >> "${EVIDENCE_FILE}"
else
    log_pass "SteamOS polkit helper: steamos-update exists"
    echo "[PASS] SteamOS polkit helper: steamos-update exists" >> "${EVIDENCE_FILE}"
fi

if [[ "${JUPITER_POLKIT_BIOS_EXISTS}" != "yes" ]]; then
    log_fail "SteamOS polkit helper: jupiter-biosupdate not found"
    echo "[FAIL] SteamOS polkit helper: jupiter-biosupdate not found" >> "${EVIDENCE_FILE}"
else
    log_pass "SteamOS polkit helper: jupiter-biosupdate exists"
    echo "[PASS] SteamOS polkit helper: jupiter-biosupdate exists" >> "${EVIDENCE_FILE}"
fi

echo "" >> "${EVIDENCE_FILE}"
echo "=== Home Deck Symlink ===" >> "${EVIDENCE_FILE}"

log_info "Checking /home/deck symlink..."
DECK_LINK_EXISTS=$(docker exec "${CONTAINER_NAME}" test -L /home/deck && echo "yes" || echo "no")
DECK_DIR_EXISTS=$(docker exec "${CONTAINER_NAME}" test -d /home/deck && echo "yes" || echo "no")

{
    echo "/home/deck is symlink: ${DECK_LINK_EXISTS}"
    echo "/home/deck is directory: ${DECK_DIR_EXISTS}"
} >> "${EVIDENCE_FILE}"

if [[ "${DECK_LINK_EXISTS}" == "yes" || "${DECK_DIR_EXISTS}" == "yes" ]]; then
    log_pass "/home/deck exists (symlink or directory)"
    echo "[PASS] /home/deck exists (symlink or directory)" >> "${EVIDENCE_FILE}"
else
    log_fail "/home/deck not found"
    echo "[FAIL] /home/deck not found" >> "${EVIDENCE_FILE}"
fi

echo "" >> "${EVIDENCE_FILE}"
echo "=== Steam Runtime Directories ===" >> "${EVIDENCE_FILE}"

log_info "Checking Steam runtime directories..."

STEAM_DIR_EXISTS=$(docker exec "${CONTAINER_NAME}" test -d /root/.steam && echo "yes" || echo "no")
STEAM_RUNTIME_EXISTS=$(docker exec "${CONTAINER_NAME}" test -d /root/.steam/ubuntu12_32/steam-runtime && echo "yes" || echo "no")
CEF_DEBUG_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /root/.steam/debian-installation/.cef-enable-remote-debugging && echo "yes" || echo "no")

{
    echo "/root/.steam/: ${STEAM_DIR_EXISTS}"
    echo "/root/.steam/ubuntu12_32/steam-runtime/: ${STEAM_RUNTIME_EXISTS}"
    echo "/root/.steam/debian-installation/.cef-enable-remote-debugging: ${CEF_DEBUG_EXISTS}"
} >> "${EVIDENCE_FILE}"

if [[ "${STEAM_DIR_EXISTS}" != "yes" ]]; then
    log_fail "Steam directory: /root/.steam/ not found"
    echo "[FAIL] Steam directory: /root/.steam/ not found" >> "${EVIDENCE_FILE}"
else
    log_pass "Steam directory: /root/.steam/ exists"
    echo "[PASS] Steam directory: /root/.steam/ exists" >> "${EVIDENCE_FILE}"
fi

if [[ "${STEAM_RUNTIME_EXISTS}" != "yes" ]]; then
    log_fail "Steam runtime: /root/.steam/ubuntu12_32/steam-runtime/ not found"
    echo "[FAIL] Steam runtime: /root/.steam/ubuntu12_32/steam-runtime/ not found" >> "${EVIDENCE_FILE}"
else
    log_pass "Steam runtime: /root/.steam/ubuntu12_32/steam-runtime/ exists"
    echo "[PASS] Steam runtime: /root/.steam/ubuntu12_32/steam-runtime/ exists" >> "${EVIDENCE_FILE}"
fi

if [[ "${CEF_DEBUG_EXISTS}" != "yes" ]]; then
    log_fail "CEF debug flag: /root/.steam/debian-installation/.cef-enable-remote-debugging not found"
    echo "[FAIL] CEF debug flag: /root/.steam/debian-installation/.cef-enable-remote-debugging not found" >> "${EVIDENCE_FILE}"
else
    log_pass "CEF debug flag: /root/.steam/debian-installation/.cef-enable-remote-debugging exists"
    echo "[PASS] CEF debug flag: /root/.steam/debian-installation/.cef-enable-remote-debugging exists" >> "${EVIDENCE_FILE}"
fi

echo "" >> "${EVIDENCE_FILE}"
echo "=== Stub Exit Codes ===" >> "${EVIDENCE_FILE}"

log_info "Checking steamos-update exit code (expected: 7)..."
set +e
STEAMOS_EXIT_CODE=$(docker exec "${CONTAINER_NAME}" /usr/bin/steamos-update; echo $?)
set -e

{
    echo "steamos-update exit code: ${STEAMOS_EXIT_CODE} (expected: 7)"
} >> "${EVIDENCE_FILE}"

if [[ "${STEAMOS_EXIT_CODE}" == "7" ]]; then
    log_pass "steamos-update exits with code 7"
    echo "[PASS] steamos-update exits with code 7" >> "${EVIDENCE_FILE}"
else
    log_fail "steamos-update exit code is ${STEAMOS_EXIT_CODE}, expected 7"
    echo "[FAIL] steamos-update exit code is ${STEAMOS_EXIT_CODE}, expected 7" >> "${EVIDENCE_FILE}"
fi

log_info "Checking jupiter-biosupdate exit code (expected: 0)..."
set +e
JUPITER_EXIT_CODE=$(docker exec "${CONTAINER_NAME}" /usr/bin/jupiter-biosupdate; echo $?)
set -e

{
    echo "jupiter-biosupdate exit code: ${JUPITER_EXIT_CODE} (expected: 0)"
} >> "${EVIDENCE_FILE}"

if [[ "${JUPITER_EXIT_CODE}" == "0" ]]; then
    log_pass "jupiter-biosupdate exits with code 0"
    echo "[PASS] jupiter-biosupdate exits with code 0" >> "${EVIDENCE_FILE}"
else
    log_fail "jupiter-biosupdate exit code is ${JUPITER_EXIT_CODE}, expected 0"
    echo "[FAIL] jupiter-biosupdate exit code is ${JUPITER_EXIT_CODE}, expected 0" >> "${EVIDENCE_FILE}"
fi

echo "" >> "${EVIDENCE_FILE}"

if [[ ${FAILED} -eq 0 ]]; then
    echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
    log_info "All Steam compatibility checks passed"
    echo ""
    echo "=== TEST PASSED ==="
    exit 0
else
    echo "RESULT: FAILED" >> "${EVIDENCE_FILE}"
    log_error "Steam compatibility validation failed"
    echo ""
    echo "=== TEST FAILED ==="
    exit 1
fi
