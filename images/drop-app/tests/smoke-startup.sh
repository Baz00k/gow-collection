#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/drop-app:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-startup-drop-app}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/drop-app}"
EVIDENCE_FILE="${EVIDENCE_DIR}/startup.txt"
STUB_DIR=""

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

mkdir -p "${EVIDENCE_DIR}"

{
    echo "=== Smoke Test: Container Startup ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Image: ${IMAGE_NAME}"
    echo "Container: ${CONTAINER_NAME}"
    echo ""
} > "${EVIDENCE_FILE}"

cleanup() {
    log_info "Cleaning up container ${CONTAINER_NAME}..."
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    if [[ -n "${STUB_DIR}" ]]; then
        rm -rf "${STUB_DIR}"
    fi
}
trap cleanup EXIT

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    log_error "Image ${IMAGE_NAME} not found. Pull or build the image first."
    echo "ERROR: Image not found" >> "${EVIDENCE_FILE}"
    exit 1
fi

STUB_DIR="$(mktemp -d "${EVIDENCE_DIR}/startup-stub.XXXXXX")"
STUB_PATH="${STUB_DIR}/drop-app"
SENTINEL_PATH="${STUB_DIR}/invoked"
RUN_LOG="${STUB_DIR}/docker-run.log"

cat > "${STUB_PATH}" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "drop-app startup stub invoked" > "${STARTUP_SENTINEL:?}"
echo "argv: $*" >> "${STARTUP_SENTINEL}"
echo "XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-unset}" >> "${STARTUP_SENTINEL}"
echo "BROWSER: ${BROWSER:-unset}" >> "${STARTUP_SENTINEL}"
EOF
chmod +x "${STUB_PATH}"

log_info "Exercising inherited entrypoint and /opt/gow/startup.sh..."
set +e
docker run \
    --name "${CONTAINER_NAME}" \
    -e PUID=0 \
    -e STARTUP_SENTINEL=/tmp/startup-smoke/invoked \
    -v "${STUB_PATH}:/usr/bin/drop-app:ro" \
    -v "${STUB_DIR}:/tmp/startup-smoke" \
    "${IMAGE_NAME}" > "${RUN_LOG}" 2>&1
RUN_EXIT_CODE=$?
set -e

{
    echo "=== docker run output ==="
    cat "${RUN_LOG}"
    echo "=== startup stub output ==="
    if [[ -f "${SENTINEL_PATH}" ]]; then
        cat "${SENTINEL_PATH}"
    else
        echo "startup stub was not invoked"
    fi
} >> "${EVIDENCE_FILE}"

if [[ ${RUN_EXIT_CODE} -ne 0 ]]; then
    log_error "Container startup path failed"
    echo "RESULT: FAILED (startup path)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if [[ ! -f "${SENTINEL_PATH}" ]]; then
    log_error "Startup script did not invoke /usr/bin/drop-app"
    echo "RESULT: FAILED (app command not invoked)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Checking startup contract files..."
docker run --rm --entrypoint "" "${IMAGE_NAME}" test -x /opt/gow/startup.sh
docker run --rm --entrypoint "" "${IMAGE_NAME}" test ! -e /opt/gow/startup-app.sh
docker run --rm --entrypoint "" "${IMAGE_NAME}" test ! -e /opt/gow/launch-comp.sh

if ! grep -q "XDG_RUNTIME_DIR: /tmp/.X11-unix" "${SENTINEL_PATH}"; then
    log_error "XDG_RUNTIME_DIR was not set for startup path"
    echo "RESULT: FAILED (XDG_RUNTIME_DIR)" >> "${EVIDENCE_FILE}"
    exit 1
fi

if ! grep -q "BROWSER: firefox" "${SENTINEL_PATH}"; then
    log_error "BROWSER was not set for startup path"
    echo "RESULT: FAILED (BROWSER env)" >> "${EVIDENCE_FILE}"
    exit 1
fi

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"

log_info "Startup path test passed"
echo ""
echo "=== TEST PASSED ==="
exit 0
