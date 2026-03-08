#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/prism-offline:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-java}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../test-results/prism-offline}"
EVIDENCE_FILE="${EVIDENCE_DIR}/java.txt"
REQUIRED_JAVA_VERSIONS=(21 17 8)

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
    echo "=== Smoke Test: Java Runtime Availability ==="
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

log_info "Starting container for Java tests..."
docker run -d --entrypoint "" --name "${CONTAINER_NAME}" "${IMAGE_NAME}" sleep infinity >/dev/null

sleep 2

CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "${CONTAINER_NAME}")
if [[ "${CONTAINER_STATUS}" != "running" ]]; then
    log_error "Container is not running. Status: ${CONTAINER_STATUS}"
    echo "RESULT: FAILED (container not running)" >> "${EVIDENCE_FILE}"
    exit 1
fi

TEST_PASSED=true
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

{
    echo "=== Java Runtime Tests ==="
    echo ""
} >> "${EVIDENCE_FILE}"

for JAVA_VER in "${REQUIRED_JAVA_VERSIONS[@]}"; do
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log_info "Testing Java ${JAVA_VER}..."

    JAVA_CMD=""
    if docker exec "${CONTAINER_NAME}" which "java-${JAVA_VER}-openjdk-amd64" >/dev/null 2>&1; then
        JAVA_CMD="java-${JAVA_VER}-openjdk-amd64"
    elif docker exec "${CONTAINER_NAME}" which "java${JAVA_VER}" >/dev/null 2>&1; then
        JAVA_CMD="java${JAVA_VER}"
    elif docker exec "${CONTAINER_NAME}" test -f "/usr/lib/jvm/java-${JAVA_VER}-openjdk-amd64/bin/java" 2>/dev/null; then
        JAVA_CMD="/usr/lib/jvm/java-${JAVA_VER}-openjdk-amd64/bin/java"
    elif docker exec "${CONTAINER_NAME}" test -f "/usr/lib/jvm/java-${JAVA_VER}-openjdk-${JAVA_VER}-openjdk-amd64/bin/java" 2>/dev/null; then
        JAVA_CMD="/usr/lib/jvm/java-${JAVA_VER}-openjdk-${JAVA_VER}-openjdk-amd64/bin/java"
    else
        JAVA_CMD="java"
    fi

    JAVA_VERSION_OUTPUT=$(docker exec "${CONTAINER_NAME}" ${JAVA_CMD} -version 2>&1 || true)

    if echo "${JAVA_VERSION_OUTPUT}" | grep -q "version \"${JAVA_VER}\|1.${JAVA_VER}"; then
        log_info "  ✓ Java ${JAVA_VER} is available"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        {
            echo "--- Java ${JAVA_VER} ---"
            echo "Command: ${JAVA_CMD}"
            echo "Status: AVAILABLE"
            echo "Output:"
            echo "${JAVA_VERSION_OUTPUT}" | head -3
            echo ""
        } >> "${EVIDENCE_FILE}"
    else
        log_error "  ✗ Java ${JAVA_VER} not found or wrong version"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TEST_PASSED=false
        {
            echo "--- Java ${JAVA_VER} ---"
            echo "Command: ${JAVA_CMD}"
            echo "Status: MISSING or WRONG VERSION"
            echo "Output:"
            echo "${JAVA_VERSION_OUTPUT}" | head -3
            echo ""
        } >> "${EVIDENCE_FILE}"
    fi
done

log_info "Listing all Java installations..."
{
    echo "=== All Java Installations ==="
    docker exec "${CONTAINER_NAME}" bash -c 'ls -la /usr/lib/jvm/ 2>/dev/null || echo "No /usr/lib/jvm directory"'
    echo ""
    echo "=== update-alternatives java ==="
    docker exec "${CONTAINER_NAME}" update-alternatives --list java 2>/dev/null || echo "update-alternatives not configured"
    echo ""
    echo "=== Default java -version ==="
    docker exec "${CONTAINER_NAME}" java -version 2>&1 || echo "No default java"
} >> "${EVIDENCE_FILE}"

{
    echo ""
    echo "=== Summary ==="
    echo "Total Tests: ${TESTS_TOTAL}"
    echo "Passed: ${TESTS_PASSED}"
    echo "Failed: ${TESTS_FAILED}"
    echo ""
} >> "${EVIDENCE_FILE}"

if [[ "${TEST_PASSED}" != "true" ]]; then
    echo "RESULT: FAILED (${TESTS_FAILED}/${TESTS_TOTAL} tests failed)" >> "${EVIDENCE_FILE}"
    log_error "Java tests failed: ${TESTS_FAILED}/${TESTS_TOTAL}"
    exit 1
fi

echo "RESULT: PASSED (${TESTS_PASSED}/${TESTS_TOTAL} tests passed)" >> "${EVIDENCE_FILE}"

log_info "All Java tests passed (${TESTS_PASSED}/${TESTS_TOTAL})"
echo ""
echo "=== TEST PASSED ==="
exit 0
