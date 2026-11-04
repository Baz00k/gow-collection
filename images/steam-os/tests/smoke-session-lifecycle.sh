#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/baz00k/gow-collection/steam-os:test}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam-os}"
EVIDENCE_FILE="${EVIDENCE_DIR}/session-lifecycle.txt"
STUB_DIR=""
CONTAINER=""

# shellcheck disable=SC2329 # Invoked via trap.
cleanup() {
    if [[ -n "${CONTAINER}" ]]; then
        docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${STUB_DIR}" ]]; then
        rm -rf "${STUB_DIR}"
    fi
}
trap cleanup EXIT

fail() {
    echo "RESULT: FAILED ($1)" >> "${EVIDENCE_FILE}"
    echo "[ERROR] $1" >&2
    exit 1
}

mkdir -p "${EVIDENCE_DIR}"
printf '=== Smoke Test: SteamOS Session Lifecycle ===\nImage: %s\n\n' "${IMAGE_NAME}" > "${EVIDENCE_FILE}"

STUB_DIR="$(mktemp -d "${EVIDENCE_DIR}/lifecycle-stub.XXXXXX")"
SENTINEL="${STUB_DIR}/events"

cat > "${STUB_DIR}/passthrough" <<'EOF'
#!/bin/bash
# Stands in for dbus-run-session and gamescope: run the command after "--".
set -euo pipefail
export DISPLAY=:42 GAMESCOPE_WAYLAND_DISPLAY=gamescope-0 WAYLAND_DISPLAY=
while [[ "$#" -gt 0 && "$1" != "--" ]]; do
    shift
done
shift
exec "$@"
EOF

cat > "${STUB_DIR}/noop" <<'EOF'
#!/bin/bash
exit 0
EOF

# Steam stub. "-shutdown" asks the running instance to quit; the running
# instance takes a moment to exit, like the real client. With
# LIFECYCLE_LEAVE_SURVIVOR it exits at once and leaves a child behind.
cat > "${STUB_DIR}/steam" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "-shutdown" ]]; then
    touch /tmp/lifecycle/shutdown
    exit 0
fi
if [[ -n "${LIFECYCLE_LEAVE_SURVIVOR:-}" ]]; then
    # Only a SIGTERM from the supervisor records this; container teardown
    # would SIGKILL it silently.
    bash -c 'trap "echo survivor terminated >> /tmp/lifecycle/events; exit 0" TERM
             while true; do sleep 0.1; done' &
    exit 0
fi
echo "steam running" >> /tmp/lifecycle/events
while [[ ! -e /tmp/lifecycle/shutdown ]]; do
    sleep 0.2
done
sleep 3
echo "steam exited gracefully" >> /tmp/lifecycle/events
EOF

cat > "${STUB_DIR}/plasma-session" <<'EOF'
#!/bin/bash
echo "plasma started" >> /tmp/lifecycle/events
EOF

chmod +x "${STUB_DIR}"/passthrough "${STUB_DIR}"/noop "${STUB_DIR}"/steam "${STUB_DIR}"/plasma-session

STUB_MOUNTS=(
    -v "${STUB_DIR}/passthrough:/usr/bin/dbus-run-session:ro"
    -v "${STUB_DIR}/passthrough:/usr/bin/gamescope:ro"
    -v "${STUB_DIR}/noop:/usr/bin/dbus-update-activation-environment:ro"
    -v "${STUB_DIR}/noop:/usr/bin/ibus-daemon:ro"
    -v "${STUB_DIR}/steam:/usr/bin/steam:ro"
    -v "${STUB_DIR}/plasma-session:/opt/gow/steamos-plasma-session.sh:ro"
    -v "${STUB_DIR}:/tmp/lifecycle"
)

wait_for_event() {
    local event="$1"

    for _ in {1..150}; do
        grep -qxF "${event}" "${SENTINEL}" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

wait_for_container_exit() {
    local status

    if ! status="$(timeout 60 docker wait "${CONTAINER}")"; then
        fail "container did not exit"
    fi
    {
        echo "=== container output ==="
        docker logs "${CONTAINER}" 2>&1
        echo "=== events ==="
        cat "${SENTINEL}" 2>/dev/null || true
    } >> "${EVIDENCE_FILE}"
    [[ "${status}" == "0" ]] || fail "container exited with status ${status}"
}

echo "--- switch to desktop ---" >> "${EVIDENCE_FILE}"
: > "${SENTINEL}"
rm -f "${STUB_DIR}/shutdown"
CONTAINER="$(docker run -d -e PUID=0 "${STUB_MOUNTS[@]}" "${IMAGE_NAME}")"
wait_for_event "steam running" || fail "Steam did not start"
# Write to the supervisor directly: steamos-session-select also runs
# "steam -shutdown" and would hide a missing request from the supervisor.
docker exec "${CONTAINER}" bash -c 'printf "plasma\n" > /run/user/0/gow-steamos-session.cmd' \
    || fail "could not request the desktop session"
wait_for_container_exit
# The stub only exits gracefully after "steam -shutdown"; a TERM would kill it first.
for event in "steam exited gracefully" "plasma started"; do
    grep -qxF "${event}" "${SENTINEL}" || fail "missing switch event: ${event}"
done
docker rm -f "${CONTAINER}" >/dev/null
CONTAINER=""

echo "--- leftover processes after Steam exits ---" >> "${EVIDENCE_FILE}"
: > "${SENTINEL}"
CONTAINER="$(docker run -d -e PUID=0 -e LIFECYCLE_LEAVE_SURVIVOR=1 "${STUB_MOUNTS[@]}" "${IMAGE_NAME}")"
wait_for_container_exit
grep -qxF "survivor terminated" "${SENTINEL}" || fail "supervisor did not terminate the leftover process"

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
echo "[INFO] SteamOS session lifecycle smoke test passed"
