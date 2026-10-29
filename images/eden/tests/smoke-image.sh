#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/eden:test}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/eden}"
EVIDENCE_FILE="${EVIDENCE_DIR}/image.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

mkdir -p "${EVIDENCE_DIR}"

{
    echo "=== Smoke Test: Image Contents ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Image: ${IMAGE_NAME}"
    echo ""
} > "${EVIDENCE_FILE}"

fail() {
    log_error "$1"
    echo "RESULT: FAILED ($1)" >> "${EVIDENCE_FILE}"
    exit 1
}

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    fail "image ${IMAGE_NAME} not found"
fi

run_in_image() {
    docker run --rm --entrypoint "" "${IMAGE_NAME}" "$@"
}

# AppRun, bin/eden and the pinned version are asserted by the Dockerfile.
log_info "Checking bundled library resolution..."
# bin/eden is the static sharun launcher; the emulator itself is the dynamic
# ELF in shared/bin, which resolves against the bundle's own libraries.
run_in_image test -x /opt/eden/shared/bin/eden || fail "GUI binary is missing or not executable"
missing_libs="$(run_in_image bash -c '
    LD_LIBRARY_PATH=/opt/eden/shared/lib ldd /opt/eden/shared/bin/eden 2>&1 | grep "not found" || true
')"
if [[ -n "${missing_libs}" ]]; then
    echo "Missing libraries:" >> "${EVIDENCE_FILE}"
    echo "${missing_libs}" >> "${EVIDENCE_FILE}"
    fail "Eden has unresolved shared libraries"
fi

log_info "Checking that no firmware, keys, or game dumps are shipped..."
payloads="$(run_in_image bash -c '
    find /opt /home /usr/local -xdev \
        \( -name "prod.keys" -o -name "title.keys" \
           -o -name "*.nsp" -o -name "*.xci" -o -name "*.nca" \) \
        -print 2>/dev/null || true
')"
if [[ -n "${payloads}" ]]; then
    echo "Unexpected payloads:" >> "${EVIDENCE_FILE}"
    echo "${payloads}" >> "${EVIDENCE_FILE}"
    fail "image contains firmware, keys, or game dumps"
fi

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "Image contents test passed"
echo ""
echo "=== TEST PASSED ==="
exit 0
