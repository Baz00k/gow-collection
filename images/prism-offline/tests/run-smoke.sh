#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/prism-offline:test}"
SKIP_BUILD="${SKIP_BUILD:-false}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-600}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/prism-offline}"
EVIDENCE_FILE="${EVIDENCE_DIR}/all.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

log_header() {
    echo ""
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo -e "${BOLD}${BLUE}$*${NC}"
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo ""
}

log_test_start() {
    echo -e "${BOLD}[TEST]${NC} Running: $*"
}

log_test_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_test_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_test_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $*"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

mkdir -p "${EVIDENCE_DIR}"

{
    echo "=== Smoke Test Suite: All Tests ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Image: ${IMAGE_NAME}"
    echo "Skip Build: ${SKIP_BUILD}"
    echo ""
} > "${EVIDENCE_FILE}"

START_TIME=$(date +%s)

log_header "GoW Prism Offline Image - Smoke Test Suite"
echo "Image: ${IMAGE_NAME}"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo ""

TESTS_TOTAL=$((TESTS_TOTAL + 1))
log_test_start "Container Startup"
if "${SCRIPT_DIR}/smoke-startup.sh"; then
    log_test_pass "Container Startup"
    echo "1. STARTUP: PASSED" >> "${EVIDENCE_FILE}"
else
    log_test_fail "Container Startup"
    echo "1. STARTUP: FAILED" >> "${EVIDENCE_FILE}"
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
log_test_start "Java Runtime Availability"
if "${SCRIPT_DIR}/smoke-java.sh"; then
    log_test_pass "Java Runtime Availability"
    echo "2. JAVA: PASSED" >> "${EVIDENCE_FILE}"
else
    log_test_fail "Java Runtime Availability"
    echo "2. JAVA: FAILED" >> "${EVIDENCE_FILE}"
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
log_test_start "Data Persistence"
if "${SCRIPT_DIR}/smoke-persistence.sh"; then
    log_test_pass "Data Persistence"
    echo "3. PERSISTENCE: PASSED" >> "${EVIDENCE_FILE}"
else
    log_test_fail "Data Persistence"
    echo "3. PERSISTENCE: FAILED" >> "${EVIDENCE_FILE}"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

{
    echo ""
    echo "=== Summary ==="
    echo "Total: ${TESTS_TOTAL}"
    echo "Passed: ${TESTS_PASSED}"
    echo "Failed: ${TESTS_FAILED}"
    echo "Skipped: ${TESTS_SKIPPED}"
    echo "Duration: ${DURATION}s"
    echo ""
} >> "${EVIDENCE_FILE}"

log_header "Test Summary"
echo "Total Tests:   ${TESTS_TOTAL}"
echo "Passed:        ${TESTS_PASSED}"
echo "Failed:        ${TESTS_FAILED}"
echo "Skipped:       ${TESTS_SKIPPED}"
echo "Duration:      ${DURATION}s"
echo ""
echo "Evidence files written to:"
ls -la "${EVIDENCE_DIR}"/*.txt 2>/dev/null || echo "  (none)"
echo ""

if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "${RED}${BOLD}=== TESTS FAILED ===${NC}"
    echo "RESULT: FAILED" >> "${EVIDENCE_FILE}"
    exit 1
else
    echo -e "${GREEN}${BOLD}=== ALL TESTS PASSED ===${NC}"
    echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
    exit 0
fi
