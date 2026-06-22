#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/base:test}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/base}"
EVIDENCE_FILE="${EVIDENCE_DIR}/all.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

mkdir -p "${EVIDENCE_DIR}"
{
    echo "=== Smoke Test Suite: Base ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Image: ${IMAGE_NAME}"
    echo ""
} > "${EVIDENCE_FILE}"

echo -e "${BOLD}${BLUE}=== Base Image - Smoke Test Suite ===${NC}"

run_test() {
    local name="$1" script="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -e "${BOLD}[TEST]${NC} ${name}"
    if "${SCRIPT_DIR}/${script}"; then
        echo -e "${GREEN}[PASS]${NC} ${name}"
        echo "${name}: PASSED" >> "${EVIDENCE_FILE}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}[FAIL]${NC} ${name}"
        echo "${name}: FAILED" >> "${EVIDENCE_FILE}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

run_test "Runtime Contract" "smoke-runtime.sh"

{
    echo ""
    echo "=== Summary ==="
    echo "Total: ${TESTS_TOTAL}  Passed: ${TESTS_PASSED}  Failed: ${TESTS_FAILED}"
} >> "${EVIDENCE_FILE}"

echo "Total: ${TESTS_TOTAL}  Passed: ${TESTS_PASSED}  Failed: ${TESTS_FAILED}"

if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "${RED}${BOLD}=== TESTS FAILED ===${NC}"
    echo "RESULT: FAILED" >> "${EVIDENCE_FILE}"
    exit 1
fi
echo -e "${GREEN}${BOLD}=== ALL TESTS PASSED ===${NC}"
echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
exit 0
