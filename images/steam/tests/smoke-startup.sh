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
    /usr/bin/xwininfo
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

if ! docker exec "${CONTAINER_NAME}" test -x /opt/decky/PluginLoader; then
    fail "Decky PluginLoader missing or not executable"
fi
echo "/opt/decky/PluginLoader: ok" >> "${EVIDENCE_FILE}"

if ! docker exec "${CONTAINER_NAME}" test -s /opt/decky/.loader.version; then
    fail "Decky loader version marker missing"
fi
echo "/opt/decky/.loader.version: ok" >> "${EVIDENCE_FILE}"

if ! docker exec "${CONTAINER_NAME}" flatpak remotes --system | grep -q '^flathub$'; then
    fail "system Flathub remote missing"
fi
echo "system Flathub remote: ok" >> "${EVIDENCE_FILE}"

STUB_DIR="$(mktemp -d "${EVIDENCE_DIR}/startup-stub.XXXXXX")"
SENTINEL_PATH="${STUB_DIR}/invoked"
RUN_LOG="${STUB_DIR}/docker-run.log"
PLASMA_SENTINEL_PATH="${STUB_DIR}/plasma-invoked"
PLASMA_RUN_LOG="${STUB_DIR}/docker-run-plasma.log"
DISABLED_SENTINEL_PATH="${STUB_DIR}/disabled-invoked"
DISABLED_RUN_LOG="${STUB_DIR}/docker-run-disabled.log"

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
if [[ -n "${XDG_RUNTIME_DIR:-}" && -n "${WAYLAND_DISPLAY:-}" ]]; then
    mkdir -p "${XDG_RUNTIME_DIR}"
    rm -f "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
    /usr/bin/python3 - <<'PY' &
import os
import socket
import time

path = os.path.join(os.environ['XDG_RUNTIME_DIR'], os.environ['WAYLAND_DISPLAY'])
sock = socket.socket(socket.AF_UNIX)
sock.bind(path)
sock.listen(1)
time.sleep(20)
PY
    for _ in {1..50}; do
        [[ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]] && break
        sleep 0.1
    done
fi
if [[ "${1:-}" == "--" ]]; then
    shift
fi
exec "$@"
EOF
chmod +x "${STUB_DIR}/dbus-run-session"

cat > "${STUB_DIR}/dbus-update-activation-environment" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "dbus-update-activation-environment stub invoked" >> "${STARTUP_SENTINEL:?}"
echo "dbus env argv: $*" >> "${STARTUP_SENTINEL:?}"
EOF
chmod +x "${STUB_DIR}/dbus-update-activation-environment"

cat > "${STUB_DIR}/steam" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "steam stub invoked" >> "${STARTUP_SENTINEL:?}"
echo "argv: $*" >> "${STARTUP_SENTINEL}"
EOF
chmod +x "${STUB_DIR}/steam"

cat > "${STUB_DIR}/steam-game-window-tagger.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "steam-game-window-tagger stub invoked" >> "${STARTUP_SENTINEL:?}"
while true; do
    sleep 1
done
EOF
chmod +x "${STUB_DIR}/steam-game-window-tagger.sh"

cat > "${STUB_DIR}/startplasma-wayland" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "startplasma-wayland stub invoked" >> "${STARTUP_SENTINEL:?}"
mkdir -p "${XDG_RUNTIME_DIR:?}"
rm -f "${XDG_RUNTIME_DIR}/wayland-6"
/usr/bin/python3 - <<'PY' &
import os
import socket
import time

path = os.path.join(os.environ['XDG_RUNTIME_DIR'], 'wayland-6')
sock = socket.socket(socket.AF_UNIX)
sock.bind(path)
sock.listen(1)
time.sleep(8)
PY
mkdir -p /tmp/.X11-unix
rm -f /tmp/.X11-unix/X7
/usr/bin/python3 - <<'PY' &
import socket
import time

path = '/tmp/.X11-unix/X7'
sock = socket.socket(socket.AF_UNIX)
sock.bind(path)
sock.listen(1)
time.sleep(8)
PY
printf 'test-cookie\n' > /tmp/startup-smoke/xauth_test
# Spawn a fake kwin_wayland whose exec name matches `pgrep -x kwin_wayland` and
# whose cmdline carries the X11 discovery args the session script parses.
kwin_bin="/tmp/startup-smoke/kwin_wayland"
cp /bin/bash "${kwin_bin}"
"${kwin_bin}" /tmp/startup-smoke/kwin_wayland-payload.sh \
    --wayland-fd 7 \
    --socket wayland-0 \
    --xwayland-display :7 \
    --xwayland-xauthority /tmp/startup-smoke/xauth_test \
    --xwayland &
grep -q '^systemdBoot=false$' /etc/xdg/startkderc
echo "startkderc systemdBoot=false" >> "${STARTUP_SENTINEL:?}"
grep -q '^KDE_SESSION_VERSION=6$' <(env)
echo "kde session version exported" >> "${STARTUP_SENTINEL:?}"
case ":${XDG_DATA_DIRS:-}:" in
    *:${HOME}/.local/share/flatpak/exports/share:*) ;;
    *) exit 1 ;;
esac
echo "flatpak data dirs exported" >> "${STARTUP_SENTINEL:?}"
grep -q '^DefaultProfile=Shell.profile$' /etc/xdg/konsolerc
grep -q '^Command=/bin/bash$' /usr/share/konsole/Shell.profile
echo "konsole shell profile configured" >> "${STARTUP_SENTINEL:?}"
grep -q '^Autolock=false$' /etc/xdg/kscreenlockerrc
grep -q '^LockOnResume=false$' /etc/xdg/kscreenlockerrc
echo "kscreenlocker disabled" >> "${STARTUP_SENTINEL:?}"
test -x "${HOME}/Desktop/return-to-steam.desktop"
grep -q '^Exec=/usr/local/bin/return-to-steam$' "${HOME}/Desktop/return-to-steam.desktop"
echo "return-to-steam desktop shortcut installed" >> "${STARTUP_SENTINEL:?}"
sleep 8
EOF
chmod +x "${STUB_DIR}/startplasma-wayland"

# Payload run by the fake kwin_wayland process. The session script discovers
# DISPLAY and XAUTHORITY by parsing /proc/<pid>/cmdline of a process whose exec
# name is exactly "kwin_wayland". To make `pgrep -x kwin_wayland` match (it
# compares against the executable name, not argv[0]), startplasma-wayland copies
# /bin/bash to a file literally named "kwin_wayland" and runs this payload.
cat > "${STUB_DIR}/kwin_wayland-payload.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "kwin_wayland stub invoked" >> "${STARTUP_SENTINEL:?}"
sleep 8
EOF
chmod +x "${STUB_DIR}/kwin_wayland-payload.sh"

cat > "${STUB_DIR}/plasmashell" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "plasmashell stub invoked" >> "${STARTUP_SENTINEL:?}"
echo "argv: $*" >> "${STARTUP_SENTINEL:?}"
echo "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}" >> "${STARTUP_SENTINEL:?}"
echo "DISPLAY=${DISPLAY:-}" >> "${STARTUP_SENTINEL:?}"
echo "XAUTHORITY=${XAUTHORITY:-}" >> "${STARTUP_SENTINEL:?}"
EOF
chmod +x "${STUB_DIR}/plasmashell"

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
    -v "${STUB_DIR}/firefox:/usr/bin/firefox:ro" \
    -v "${STUB_DIR}/steam-game-window-tagger.sh:/opt/gow/steam-game-window-tagger.sh:ro" \
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
    "steam-game-window-tagger stub invoked" \
    "dbus-run-session stub invoked" \
    "steam stub invoked" \
    "argv: -gamepadui -steamos3 -steampal -steamdeck"; do
    if ! grep -qF "${expected}" "${SENTINEL_PATH}"; then
        fail "missing startup evidence: ${expected}"
    fi
done

log_info "Exercising Steam startup with window tagger disabled..."
rm -f "${DISABLED_SENTINEL_PATH}"
set +e
docker run \
    --rm \
    -e PUID=0 \
    -e STARTUP_SENTINEL=/tmp/startup-smoke/disabled-invoked \
    -e STEAM_STARTUP_FLAGS="-gamepadui -steamos3 -steampal -steamdeck" \
    -e STEAM_WINDOW_TAGGER=off \
    -e PATH=/tmp/startup-smoke:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    -v "${STUB_DIR}/gamescope:/usr/bin/gamescope:ro" \
    -v "${STUB_DIR}/ibus-daemon:/usr/bin/ibus-daemon:ro" \
    -v "${STUB_DIR}/dbus-run-session:/usr/bin/dbus-run-session:ro" \
    -v "${STUB_DIR}/steam:/usr/bin/steam:ro" \
    -v "${STUB_DIR}/steam-game-window-tagger.sh:/opt/gow/steam-game-window-tagger.sh:ro" \
    -v "${STUB_DIR}:/tmp/startup-smoke" \
    "${IMAGE_NAME}" > "${DISABLED_RUN_LOG}" 2>&1
DISABLED_RUN_EXIT_CODE=$?
set -e

{
    echo "=== disabled window tagger startup output ==="
    cat "${DISABLED_RUN_LOG}"
    echo "=== disabled window tagger stub output ==="
    if [[ -f "${DISABLED_SENTINEL_PATH}" ]]; then
        cat "${DISABLED_SENTINEL_PATH}"
    else
        echo "startup stubs were not invoked"
    fi
} >> "${EVIDENCE_FILE}"

if [[ ${DISABLED_RUN_EXIT_CODE} -ne 0 ]]; then
    fail "startup path with disabled window tagger failed"
fi

for expected in \
    "gamescope stub invoked" \
    "ibus-daemon stub invoked" \
    "dbus-run-session stub invoked" \
    "steam stub invoked"; do
    if ! grep -qF "${expected}" "${DISABLED_SENTINEL_PATH}"; then
        fail "missing disabled-window-tagger startup evidence: ${expected}"
    fi
done
if grep -qF "steam-game-window-tagger stub invoked" "${DISABLED_SENTINEL_PATH}"; then
    fail "Steam game window tagger started despite STEAM_WINDOW_TAGGER=off"
fi
if ! grep -qF "Steam game window tagger disabled by STEAM_WINDOW_TAGGER=off" "${DISABLED_RUN_LOG}"; then
    fail "missing disabled window tagger log evidence"
fi

log_info "Exercising Plasma startup path..."
rm -f "${PLASMA_SENTINEL_PATH}"
set +e
docker run \
    --rm \
    -e PUID=0 \
    -e STEAMOS_SESSION=plasma \
    -e XDG_RUNTIME_DIR=/tmp/plasma-runtime \
    -e WAYLAND_DISPLAY=wayland-3 \
    -e STARTUP_SENTINEL=/tmp/startup-smoke/plasma-invoked \
    -e PATH=/tmp/startup-smoke:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    -v "${STUB_DIR}/dbus-run-session:/usr/bin/dbus-run-session:ro" \
    -v "${STUB_DIR}/dbus-update-activation-environment:/usr/bin/dbus-update-activation-environment:ro" \
    -v "${STUB_DIR}/startplasma-wayland:/usr/bin/startplasma-wayland:ro" \
    -v "${STUB_DIR}/plasmashell:/usr/bin/plasmashell:ro" \
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
    "dbus-run-session stub invoked" \
    "dbus-update-activation-environment stub invoked" \
    "dbus env argv: WAYLAND_DISPLAY DISPLAY XAUTHORITY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS HOME PATH XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE KDE_FULL_SESSION KDE_SESSION_VERSION XDG_DATA_DIRS" \
    "startplasma-wayland stub invoked" \
    "kwin_wayland stub invoked" \
    "startkderc systemdBoot=false" \
    "kde session version exported" \
    "flatpak data dirs exported" \
    "konsole shell profile configured" \
    "kscreenlocker disabled" \
    "return-to-steam desktop shortcut installed" \
    "plasmashell stub invoked" \
    "argv: --replace" \
    "WAYLAND_DISPLAY=wayland-6" \
    "DISPLAY=:7" \
    "XAUTHORITY=/tmp/startup-smoke/xauth_test"; do
    if ! grep -qF "${expected}" "${PLASMA_SENTINEL_PATH}"; then
        fail "missing plasma startup evidence: ${expected}"
    fi
done

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "Steam startup smoke test passed"
exit 0
