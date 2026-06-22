#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/steam:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-startup-steam}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam}"
EVIDENCE_FILE="${EVIDENCE_DIR}/startup.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

mkdir -p "${EVIDENCE_DIR}"
{
    echo "=== Smoke Test: Steam Startup ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Image: ${IMAGE_NAME}"
    echo "Container: ${CONTAINER_NAME}"
    echo ""
} > "${EVIDENCE_FILE}"

cleanup() { docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true; }
trap cleanup EXIT

fail() {
    log_error "$1"
    echo "RESULT: FAILED ($1)" >> "${EVIDENCE_FILE}"
    exit 1
}

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    fail "image not found"
fi

log_info "Starting container..."
docker run -d --entrypoint "" --name "${CONTAINER_NAME}" "${IMAGE_NAME}" sleep infinity >/dev/null
sleep 2

if [[ "$(docker inspect --format='{{.State.Status}}' "${CONTAINER_NAME}")" != "running" ]]; then
    fail "container not running"
fi

REQUIRED_EXEC=(
    /opt/gow/startup.sh
    /usr/bin/steam
    /usr/bin/gamescope
)

for f in "${REQUIRED_EXEC[@]}"; do
    if ! docker exec "${CONTAINER_NAME}" test -x "$f"; then
        fail "missing or not executable ${f}"
    fi
    echo "${f}: ok" >> "${EVIDENCE_FILE}"
done

if ! docker exec "${CONTAINER_NAME}" test -x /opt/gow/entrypoint.sh; then
    fail "base entrypoint missing"
fi
echo "/opt/gow/entrypoint.sh: ok" >> "${EVIDENCE_FILE}"

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "Steam startup smoke test passed"
exit 0
