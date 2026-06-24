#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/baz00k/gow-collection/steam:test}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam}"
EVIDENCE_FILE="${EVIDENCE_DIR}/all.txt"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

mkdir -p "${EVIDENCE_DIR}"
{
    echo "=== Smoke Test Suite: Steam ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Image: ${IMAGE_NAME}"
    echo ""
} > "${EVIDENCE_FILE}"

FAILED=0
for TEST_SCRIPT in "${SCRIPT_DIR}"/smoke-*.sh; do
    TEST_NAME="$(basename "${TEST_SCRIPT}" .sh)"
    echo "Running ${TEST_NAME} against ${IMAGE_NAME}"
    if "${TEST_SCRIPT}"; then
        echo "${TEST_NAME}: PASSED" >> "${EVIDENCE_FILE}"
    else
        echo "${TEST_NAME}: FAILED" >> "${EVIDENCE_FILE}"
        FAILED=1
    fi
done

if [[ ${FAILED} -eq 0 ]]; then
    echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
    echo -e "${GREEN}[PASS]${NC} Steam smoke test passed"
    exit 0
fi

echo "RESULT: FAILED" >> "${EVIDENCE_FILE}"
echo -e "${RED}[FAIL]${NC} Steam smoke test failed"
exit 1
