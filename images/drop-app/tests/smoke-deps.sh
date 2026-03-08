#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/drop-app:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-deps-drop-app}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../test-results/drop-app}"
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

log_info "Checking binary: drop-app..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v drop-app' >/dev/null 2>&1; then
    log_pass "Binary: drop-app"
    echo "[PASS] Binary: drop-app" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: drop-app - not found in PATH"
    echo "[FAIL] Binary: drop-app - not found in PATH" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: firefox..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v firefox' >/dev/null 2>&1; then
    log_pass "Binary: firefox"
    echo "[PASS] Binary: firefox" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: firefox - not found in PATH"
    echo "[FAIL] Binary: firefox - not found in PATH" >> "${EVIDENCE_FILE}"
fi

log_info "Checking binary: xdg-open..."
if docker exec "${CONTAINER_NAME}" sh -c 'command -v xdg-open' >/dev/null 2>&1; then
    log_pass "Binary: xdg-open"
    echo "[PASS] Binary: xdg-open" >> "${EVIDENCE_FILE}"
else
    log_fail "Binary: xdg-open - not found in PATH"
    echo "[FAIL] Binary: xdg-open - not found in PATH" >> "${EVIDENCE_FILE}"
fi

echo "" >> "${EVIDENCE_FILE}"
echo "=== Firefox Snap Check ===" >> "${EVIDENCE_FILE}"

log_info "Checking firefox is not a snap stub..."
if docker exec "${CONTAINER_NAME}" sh -c 'firefox --version' >/dev/null 2>&1; then
    FIREFOX_VERSION=$(docker exec "${CONTAINER_NAME}" sh -c 'firefox --version 2>&1' || echo "unknown")
    log_pass "Firefox is a real binary (not snap stub)"
    echo "[PASS] Firefox is a real binary (not snap stub) - ${FIREFOX_VERSION}" >> "${EVIDENCE_FILE}"
else
    log_fail "Firefox is a snap stub - cannot run in Docker"
    echo "[FAIL] Firefox is a snap stub - cannot run in Docker" >> "${EVIDENCE_FILE}"
fi

echo "" >> "${EVIDENCE_FILE}"
echo "=== Library Checks ===" >> "${EVIDENCE_FILE}"

log_info "Checking library: libayatana-appindicator3..."
if docker exec "${CONTAINER_NAME}" sh -c 'ldconfig -p 2>/dev/null | grep -q "libayatana-appindicator3"'; then
    log_pass "Library: libayatana-appindicator3"
    echo "[PASS] Library: libayatana-appindicator3" >> "${EVIDENCE_FILE}"
else
    log_fail "Library: libayatana-appindicator3 - not loadable"
    echo "[FAIL] Library: libayatana-appindicator3 - not loadable" >> "${EVIDENCE_FILE}"
fi

log_info "Checking library: libwebkit2gtk-4.1..."
if docker exec "${CONTAINER_NAME}" sh -c 'ldconfig -p 2>/dev/null | grep -q "libwebkit2gtk-4.1"'; then
    log_pass "Library: libwebkit2gtk-4.1"
    echo "[PASS] Library: libwebkit2gtk-4.1" >> "${EVIDENCE_FILE}"
else
    log_fail "Library: libwebkit2gtk-4.1 - not loadable"
    echo "[FAIL] Library: libwebkit2gtk-4.1 - not loadable" >> "${EVIDENCE_FILE}"
fi

echo "" >> "${EVIDENCE_FILE}"
echo "=== File Checks ===" >> "${EVIDENCE_FILE}"

log_info "Checking startup script: /opt/gow/startup-app.sh..."
if docker exec "${CONTAINER_NAME}" test -f /opt/gow/startup-app.sh; then
    if docker exec "${CONTAINER_NAME}" test -x /opt/gow/startup-app.sh; then
        log_pass "File: /opt/gow/startup-app.sh (executable)"
        echo "[PASS] File: /opt/gow/startup-app.sh (executable)" >> "${EVIDENCE_FILE}"
    else
        log_fail "File: /opt/gow/startup-app.sh - not executable"
        echo "[FAIL] File: /opt/gow/startup-app.sh - not executable" >> "${EVIDENCE_FILE}"
    fi
else
    log_fail "File: /opt/gow/startup-app.sh - does not exist"
    echo "[FAIL] File: /opt/gow/startup-app.sh - does not exist" >> "${EVIDENCE_FILE}"
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
