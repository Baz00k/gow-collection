#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/steam:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-steam-compat-steam}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam}"
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
DECK_LINK_TARGET=$(docker exec "${CONTAINER_NAME}" sh -c 'if test -L /home/deck; then readlink /home/deck; fi')

{
    echo "/home/deck is symlink: ${DECK_LINK_EXISTS}"
    echo "/home/deck is directory: ${DECK_DIR_EXISTS}"
    echo "/home/deck target: ${DECK_LINK_TARGET:-<not-a-symlink>}"
} >> "${EVIDENCE_FILE}"

if [[ "${DECK_LINK_EXISTS}" == "yes" || "${DECK_DIR_EXISTS}" == "yes" ]]; then
    log_pass "/home/deck exists (symlink or directory)"
    echo "[PASS] /home/deck exists (symlink or directory)" >> "${EVIDENCE_FILE}"
else
    log_fail "/home/deck not found"
    echo "[FAIL] /home/deck not found" >> "${EVIDENCE_FILE}"
fi

if [[ "${DECK_LINK_EXISTS}" == "yes" && "${DECK_LINK_TARGET}" != "/home/retro" ]]; then
    log_fail "/home/deck points to ${DECK_LINK_TARGET}, expected /home/retro"
    echo "[FAIL] /home/deck points to ${DECK_LINK_TARGET}, expected /home/retro" >> "${EVIDENCE_FILE}"
elif [[ "${DECK_LINK_EXISTS}" == "yes" ]]; then
    log_pass "/home/deck points to /home/retro"
    echo "[PASS] /home/deck points to /home/retro" >> "${EVIDENCE_FILE}"
fi

echo "" >> "${EVIDENCE_FILE}"
echo "=== Steam Bootstrap Files ===" >> "${EVIDENCE_FILE}"

log_info "Checking Steam bootstrap files..."

STEAM_BOOTSTRAP_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz && echo "yes" || echo "no")
STEAM_LAUNCHER_EXISTS=$(docker exec "${CONTAINER_NAME}" test -f /usr/lib/steam/bin_steam.sh && echo "yes" || echo "no")
STEAM_BIN_EXISTS=$(docker exec "${CONTAINER_NAME}" test -x /usr/bin/steam && echo "yes" || echo "no")

{
    echo "/usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz: ${STEAM_BOOTSTRAP_EXISTS}"
    echo "/usr/lib/steam/bin_steam.sh: ${STEAM_LAUNCHER_EXISTS}"
    echo "/usr/bin/steam (executable): ${STEAM_BIN_EXISTS}"
} >> "${EVIDENCE_FILE}"

if [[ "${STEAM_BOOTSTRAP_EXISTS}" != "yes" ]]; then
    log_fail "Steam bootstrap tarball not found"
    echo "[FAIL] Steam bootstrap tarball not found" >> "${EVIDENCE_FILE}"
else
    log_pass "Steam bootstrap tarball exists"
    echo "[PASS] Steam bootstrap tarball exists" >> "${EVIDENCE_FILE}"
fi

if [[ "${STEAM_LAUNCHER_EXISTS}" != "yes" ]]; then
    log_fail "Steam launcher script (bin_steam.sh) not found"
    echo "[FAIL] Steam launcher script not found" >> "${EVIDENCE_FILE}"
else
    log_pass "Steam launcher script exists"
    echo "[PASS] Steam launcher script exists" >> "${EVIDENCE_FILE}"
fi

if [[ "${STEAM_BIN_EXISTS}" != "yes" ]]; then
    log_fail "Steam binary (/usr/bin/steam) not found or not executable"
    echo "[FAIL] Steam binary not found or not executable" >> "${EVIDENCE_FILE}"
else
    log_pass "Steam binary exists and is executable"
    echo "[PASS] Steam binary exists and is executable" >> "${EVIDENCE_FILE}"
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
