#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/steam:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-deps-steam}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam}"
EVIDENCE_FILE="${EVIDENCE_DIR}/deps.txt"

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
    echo "=== Smoke Test: Dependency Validation ==="
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
echo "=== Binary Checks ===" >> "${EVIDENCE_FILE}"

log_info "Checking binary: steam..."
if docker exec "${CONTAINER_NAME}" test -f /usr/bin/steam; then
    log_pass "Binary: /usr/bin/steam"
    echo "[PASS] Binary: /usr/bin/steam" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: /usr/bin/steam - not found"
    echo "[FAIL] Binary: /usr/bin/steam - not found" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: gamescope..."
if docker exec "${CONTAINER_NAME}" test -f /usr/bin/gamescope; then
    log_pass "Binary: /usr/bin/gamescope"
    echo "[PASS] Binary: /usr/bin/gamescope" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: /usr/bin/gamescope - not found"
    echo "[FAIL] Binary: /usr/bin/gamescope - not found" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: mangohud..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v mangohud' >/dev/null 2>&1; then
    log_pass "Binary: mangohud"
    echo "[PASS] Binary: mangohud" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: mangohud - not found in PATH"
    echo "[FAIL] Binary: mangohud - not found in PATH" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: mangoapp..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v mangoapp' >/dev/null 2>&1; then
    log_pass "Binary: mangoapp"
    echo "[PASS] Binary: mangoapp" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: mangoapp - not found in PATH"
    echo "[FAIL] Binary: mangoapp - not found in PATH" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: gamemoded..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v gamemoded' >/dev/null 2>&1; then
    log_pass "Binary: gamemoded"
    echo "[PASS] Binary: gamemoded" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: gamemoded - not found in PATH"
    echo "[FAIL] Binary: gamemoded - not found in PATH" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: ibus-daemon..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v ibus-daemon' >/dev/null 2>&1; then
    log_pass "Binary: ibus-daemon"
    echo "[PASS] Binary: ibus-daemon" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: ibus-daemon - not found in PATH"
    echo "[FAIL] Binary: ibus-daemon - not found in PATH" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: dbus-daemon..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v dbus-daemon' >/dev/null 2>&1; then
    log_pass "Binary: dbus-daemon"
    echo "[PASS] Binary: dbus-daemon" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: dbus-daemon - not found in PATH"
    echo "[FAIL] Binary: dbus-daemon - not found in PATH" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: NetworkManager..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v NetworkManager' >/dev/null 2>&1; then
    log_pass "Binary: NetworkManager"
    echo "[PASS] Binary: NetworkManager" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: NetworkManager - not found in PATH"
    echo "[FAIL] Binary: NetworkManager - not found in PATH" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: /usr/libexec/bluetooth/bluetoothd..."
if docker exec "${CONTAINER_NAME}" test -f /usr/libexec/bluetooth/bluetoothd; then
    log_pass "Binary: /usr/libexec/bluetooth/bluetoothd"
    echo "[PASS] Binary: /usr/libexec/bluetooth/bluetoothd" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: /usr/libexec/bluetooth/bluetoothd - not found"
    echo "[FAIL] Binary: /usr/libexec/bluetooth/bluetoothd - not found" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: curl..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v curl' >/dev/null 2>&1; then
    log_pass "Binary: curl"
    echo "[PASS] Binary: curl" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: curl - not found in PATH"
    echo "[FAIL] Binary: curl - not found in PATH" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: jq..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v jq' >/dev/null 2>&1; then
    log_pass "Binary: jq"
    echo "[PASS] Binary: jq" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: jq - not found in PATH"
    echo "[FAIL] Binary: jq - not found in PATH" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: python3..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v python3' >/dev/null 2>&1; then
    log_pass "Binary: python3"
    echo "[PASS] Binary: python3" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: python3 - not found in PATH"
    echo "[FAIL] Binary: python3 - not found in PATH" >> "${EVIDENCE_FILE}"
fi

echo "" >> "${EVIDENCE_FILE}"
echo "=== Package Checks (rpm -q) ===" >> "${EVIDENCE_FILE}"

log_info "Checking package: steam..."
if docker exec "${CONTAINER_NAME}" rpm -q steam >/dev/null 2>&1; then
    STEAM_VER=$(docker exec "${CONTAINER_NAME}" rpm -q steam 2>/dev/null || echo "unknown")
    log_pass "Package: steam (${STEAM_VER})"
    echo "[PASS] Package: steam (${STEAM_VER})" >> "${EVIDENCE_FILE}"
else
    log_fail "Package: steam - not installed"
    echo "[FAIL] Package: steam - not installed" >> "${EVIDENCE_FILE}"
fi

log_info "Checking package: gamescope..."
if docker exec "${CONTAINER_NAME}" rpm -q gamescope >/dev/null 2>&1; then
    GAMESCOPE_VER=$(docker exec "${CONTAINER_NAME}" rpm -q gamescope 2>/dev/null || echo "unknown")
    log_pass "Package: gamescope (${GAMESCOPE_VER})"
    echo "[PASS] Package: gamescope (${GAMESCOPE_VER})" >> "${EVIDENCE_FILE}"
else
    log_fail "Package: gamescope - not installed"
    echo "[FAIL] Package: gamescope - not installed" >> "${EVIDENCE_FILE}"
fi

log_info "Checking package: mangohud..."
if docker exec "${CONTAINER_NAME}" rpm -q mangohud >/dev/null 2>&1; then
    MANGOHUD_VER=$(docker exec "${CONTAINER_NAME}" rpm -q mangohud 2>/dev/null || echo "unknown")
    log_pass "Package: mangohud (${MANGOHUD_VER})"
    echo "[PASS] Package: mangohud (${MANGOHUD_VER})" >> "${EVIDENCE_FILE}"
else
    log_fail "Package: mangohud - not installed"
    echo "[FAIL] Package: mangohud - not installed" >> "${EVIDENCE_FILE}"
fi

log_info "Checking package: gamemode..."
if docker exec "${CONTAINER_NAME}" rpm -q gamemode >/dev/null 2>&1; then
    GAMEMODE_VER=$(docker exec "${CONTAINER_NAME}" rpm -q gamemode 2>/dev/null || echo "unknown")
    log_pass "Package: gamemode (${GAMEMODE_VER})"
    echo "[PASS] Package: gamemode (${GAMEMODE_VER})" >> "${EVIDENCE_FILE}"
else
    log_fail "Package: gamemode - not installed"
    echo "[FAIL] Package: gamemode - not installed" >> "${EVIDENCE_FILE}"
fi

echo "" >> "${EVIDENCE_FILE}"
echo "=== Decky Loader ===" >> "${EVIDENCE_FILE}"

log_info "Checking Decky Loader: /opt/decky/PluginLoader..."
if docker exec "${CONTAINER_NAME}" test -f /opt/decky/PluginLoader; then
    if docker exec "${CONTAINER_NAME}" test -x /opt/decky/PluginLoader; then
        log_pass "Decky Loader: /opt/decky/PluginLoader (executable)"
        echo "[PASS] Decky Loader: /opt/decky/PluginLoader (executable)" >> "${EVIDENCE_FILE}"
    else
        log_fail "Decky Loader: /opt/decky/PluginLoader - not executable"
        echo "[FAIL] Decky Loader: /opt/decky/PluginLoader - not executable" >> "${EVIDENCE_FILE}"
    fi
else
    log_fail "Decky Loader: /opt/decky/PluginLoader - not found"
    echo "[FAIL] Decky Loader: /opt/decky/PluginLoader - not found" >> "${EVIDENCE_FILE}"
fi

echo "" >> "${EVIDENCE_FILE}"

if [[ ${FAILED} -eq 0 ]]; then
    echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
    log_info "All dependency checks passed"
    echo ""
    echo "=== TEST PASSED ==="
    exit 0
else
    echo "RESULT: FAILED" >> "${EVIDENCE_FILE}"
    log_error "Dependency validation failed"
    echo ""
    echo "=== TEST FAILED ==="
    exit 1
fi
