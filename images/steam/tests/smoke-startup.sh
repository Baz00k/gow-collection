#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/baz00k/gow-collection/steam:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-startup-steam}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam}"
EVIDENCE_FILE="${EVIDENCE_DIR}/startup.txt"
STUB_DIR=""

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

# shellcheck disable=SC2329 # Invoked via trap.
cleanup() {
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    if [[ -n "${STUB_DIR}" ]]; then
        rm -rf "${STUB_DIR}"
    fi
}
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
    /opt/gow/steamos-session-supervisor.sh
    /opt/gow/steamos-session-runner.sh
    /opt/gow/steamos-plasma-session.sh
    /usr/bin/steam
    /usr/bin/steamos-session-select
    /usr/bin/gamescope
    /usr/bin/flatpak
    /usr/bin/firefox
    /usr/local/bin/return-to-steam
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

STUB_DIR="$(mktemp -d "${EVIDENCE_DIR}/startup-stub.XXXXXX")"
SENTINEL_PATH="${STUB_DIR}/invoked"
RUN_LOG="${STUB_DIR}/docker-run.log"
PLASMA_SENTINEL_PATH="${STUB_DIR}/plasma-invoked"
PLASMA_RUN_LOG="${STUB_DIR}/docker-run-plasma.log"

cat > "${STUB_DIR}/gamescope" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "gamescope stub invoked" > "${STARTUP_SENTINEL:?}"
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "-R" ]]; then
        socket="$2"
        shift 2
        continue
    fi
    if [[ "$1" == "--" ]]; then
        shift
        exec "$@"
    fi
    shift
done
printf ':42 gamescope-0\n' > "${socket:?}"
while true; do
    sleep 1
done
EOF
chmod +x "${STUB_DIR}/gamescope"

cat > "${STUB_DIR}/ibus-daemon" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "ibus-daemon stub invoked" >> "${STARTUP_SENTINEL:?}"
EOF
chmod +x "${STUB_DIR}/ibus-daemon"

cat > "${STUB_DIR}/dbus-run-session" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "dbus-run-session stub invoked" >> "${STARTUP_SENTINEL:?}"
if [[ "${1:-}" == "--" ]]; then
    shift
fi
exec "$@"
EOF
chmod +x "${STUB_DIR}/dbus-run-session"

cat > "${STUB_DIR}/steam" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "steam stub invoked" >> "${STARTUP_SENTINEL:?}"
echo "argv: $*" >> "${STARTUP_SENTINEL}"
EOF
chmod +x "${STUB_DIR}/steam"

cat > "${STUB_DIR}/flatpak" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "flatpak stub invoked" >> "${STARTUP_SENTINEL:?}"
EOF
chmod +x "${STUB_DIR}/flatpak"

cat > "${STUB_DIR}/startplasma-wayland" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "startplasma-wayland stub invoked" >> "${STARTUP_SENTINEL:?}"
grep -q '^systemdBoot=false$' /etc/xdg/startkderc
echo "startkderc systemdBoot=false" >> "${STARTUP_SENTINEL:?}"
EOF
chmod +x "${STUB_DIR}/startplasma-wayland"

cat > "${STUB_DIR}/firefox" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "firefox stub invoked" >> "${STARTUP_SENTINEL:?}"
EOF
chmod +x "${STUB_DIR}/firefox"

log_info "Exercising default Steam startup path..."
set +e
docker run \
    --rm \
    -e PUID=0 \
    -e STARTUP_SENTINEL=/tmp/startup-smoke/invoked \
    -e STEAM_STARTUP_FLAGS="-gamepadui -steamos3 -steampal -steamdeck" \
    -e PATH=/tmp/startup-smoke:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    -v "${STUB_DIR}/gamescope:/usr/bin/gamescope:ro" \
    -v "${STUB_DIR}/ibus-daemon:/usr/bin/ibus-daemon:ro" \
    -v "${STUB_DIR}/dbus-run-session:/usr/bin/dbus-run-session:ro" \
    -v "${STUB_DIR}/steam:/usr/bin/steam:ro" \
    -v "${STUB_DIR}/flatpak:/usr/bin/flatpak:ro" \
    -v "${STUB_DIR}/firefox:/usr/bin/firefox:ro" \
    -v "${STUB_DIR}:/tmp/startup-smoke" \
    "${IMAGE_NAME}" > "${RUN_LOG}" 2>&1
RUN_EXIT_CODE=$?
set -e

{
    echo "=== default startup output ==="
    cat "${RUN_LOG}"
    echo "=== default startup stub output ==="
    if [[ -f "${SENTINEL_PATH}" ]]; then
        cat "${SENTINEL_PATH}"
    else
        echo "startup stubs were not invoked"
    fi
} >> "${EVIDENCE_FILE}"

if [[ ${RUN_EXIT_CODE} -ne 0 ]]; then
    fail "default startup path failed"
fi

for expected in \
    "gamescope stub invoked" \
    "ibus-daemon stub invoked" \
    "dbus-run-session stub invoked" \
    "steam stub invoked" \
    "argv: -gamepadui -steamos3 -steampal -steamdeck"; do
    if ! grep -qF "${expected}" "${SENTINEL_PATH}"; then
        fail "missing startup evidence: ${expected}"
    fi
done

log_info "Exercising Plasma startup path..."
rm -f "${PLASMA_SENTINEL_PATH}"
set +e
docker run \
    --rm \
    -e PUID=0 \
    -e STEAMOS_SESSION=plasma \
    -e STARTUP_SENTINEL=/tmp/startup-smoke/plasma-invoked \
    -e PATH=/tmp/startup-smoke:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    -v "${STUB_DIR}/dbus-run-session:/usr/bin/dbus-run-session:ro" \
    -v "${STUB_DIR}/flatpak:/usr/bin/flatpak:ro" \
    -v "${STUB_DIR}/startplasma-wayland:/usr/bin/startplasma-wayland:ro" \
    -v "${STUB_DIR}:/tmp/startup-smoke" \
    "${IMAGE_NAME}" > "${PLASMA_RUN_LOG}" 2>&1
PLASMA_RUN_EXIT_CODE=$?
set -e

{
    echo "=== plasma startup output ==="
    cat "${PLASMA_RUN_LOG}"
    echo "=== plasma startup stub output ==="
    if [[ -f "${PLASMA_SENTINEL_PATH}" ]]; then
        cat "${PLASMA_SENTINEL_PATH}"
    else
        echo "plasma stubs were not invoked"
    fi
} >> "${EVIDENCE_FILE}"

if [[ ${PLASMA_RUN_EXIT_CODE} -ne 0 ]]; then
    fail "plasma startup path failed"
fi

for expected in \
    "flatpak stub invoked" \
    "dbus-run-session stub invoked" \
    "startplasma-wayland stub invoked" \
    "startkderc systemdBoot=false"; do
    if ! grep -qF "${expected}" "${PLASMA_SENTINEL_PATH}"; then
        fail "missing plasma startup evidence: ${expected}"
    fi
done

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "Steam startup smoke test passed"
exit 0
