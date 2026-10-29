#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/base:test}"
CONTAINER_NAME="${CONTAINER_NAME:-smoke-test-runtime-base}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/base}"
EVIDENCE_FILE="${EVIDENCE_DIR}/runtime.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

mkdir -p "${EVIDENCE_DIR}"
{
    echo "=== Smoke Test: Base Runtime Contract ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Image: ${IMAGE_NAME}"
    echo ""
} > "${EVIDENCE_FILE}"

# shellcheck disable=SC2329 # Invoked via trap.
cleanup() { docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true; }
trap cleanup EXIT

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    log_error "Image ${IMAGE_NAME} not found."
    echo "RESULT: FAILED (image not found)" >> "${EVIDENCE_FILE}"
    exit 1
fi

log_info "Starting container..."
docker run -d --entrypoint "" --name "${CONTAINER_NAME}" "${IMAGE_NAME}" sleep infinity >/dev/null
sleep 2

fail() {
    log_error "$1"
    echo "RESULT: FAILED ($1)" >> "${EVIDENCE_FILE}"
    exit 1
}

# Packages the shared runtime contract depends on. Overlay scripts are covered
# by the behavioural checks below.
REQUIRED_EXEC=(
    /usr/bin/bwrap
    /usr/bin/fusermount
    /usr/bin/fusermount3
    /usr/bin/gamescope
)

for f in "${REQUIRED_EXEC[@]}"; do
    if ! docker exec "${CONTAINER_NAME}" test -x "$f"; then
        fail "missing or not executable ${f}"
    fi
    echo "${f}: ok" >> "${EVIDENCE_FILE}"
done

if docker exec "${CONTAINER_NAME}" test -u /usr/bin/bwrap; then
    fail "bwrap must not be setuid; Flatpak PID sharing requires unprivileged bwrap"
fi

if [[ "${GOW_STRICT_BWRAP_SMOKE:-0}" == "1" ]]; then
    if ! docker run --rm -e PUID=1000 -e PGID=1000 --security-opt seccomp=unconfined "${IMAGE_NAME}" \
        unshare -Ur true >/dev/null; then
        fail "runtime user cannot create unprivileged user namespaces"
    fi

    if ! docker run --rm -e PUID=1000 -e PGID=1000 --security-opt seccomp=unconfined "${IMAGE_NAME}" \
        bwrap --ro-bind / / --proc /proc --dev /dev /usr/bin/true >/dev/null; then
        fail "runtime user cannot run non-setuid bwrap"
    fi
else
    echo "strict bwrap runtime probe: skipped (set GOW_STRICT_BWRAP_SMOKE=1)" >> "${EVIDENCE_FILE}"
fi

# Gamescope helpers produce the shared session args.
if ! docker exec "${CONTAINER_NAME}" bash -c '
    source /opt/gow/gamescope-lib.sh
    GAMESCOPE_WIDTH=2560
    GAMESCOPE_HEIGHT=1440
    GAMESCOPE_REFRESH=120
    args=()
    gamescope_append_base_args args
    output="$(printf "%s\n" "${args[@]}")"
    grep -qFx -- "-W" <<< "${output}"
    grep -qFx -- "2560" <<< "${output}"
    grep -qFx -- "-H" <<< "${output}"
    grep -qFx -- "1440" <<< "${output}"
    grep -qFx -- "-r" <<< "${output}"
    grep -qFx -- "120" <<< "${output}"
'; then
    fail "gamescope_append_base_args did not produce expected args"
fi

# Without GAMESCOPE_REFRESH, gamescope must follow the virtual display refresh
# instead of being pinned to a hardcoded rate.
if ! docker exec "${CONTAINER_NAME}" bash -c '
    source /opt/gow/gamescope-lib.sh
    unset GAMESCOPE_REFRESH
    args=()
    gamescope_append_base_args args
    output="$(printf "%s\n" "${args[@]}")"
    ! grep -qFx -- "-r" <<< "${output}"
'; then
    fail "gamescope_append_base_args pinned a refresh rate without GAMESCOPE_REFRESH"
fi

if ! docker exec "${CONTAINER_NAME}" bash -n /opt/gow/launch-gamescope.sh; then
    fail "launch-gamescope.sh has a syntax error"
fi

# Run a command through the real entrypoint. The entrypoint logs to stdout
# before exec'ing the command, so take the last non-empty line as its output.
entrypoint_output() {
    docker run --rm "$@" 2>/dev/null \
        | grep -v '\[INFO\]' | grep -v '\[WARN\]' | sed '/^$/d' | tail -1 || true
}

# expect <description> <expected> <actual>
expect() {
    echo "$1: $3" >> "${EVIDENCE_FILE}"
    [[ "$3" == "$2" ]] || fail "$1 must be '$2' (got '$3')"
}

log_info "Verifying entrypoint runtime setup..."
USER_ENV=(-e PUID=1000 -e PGID=1000)
# shellcheck disable=SC2016 # Expanded inside the container.
PRINT_XDG=(bash -c 'printf "%s" "${XDG_RUNTIME_DIR}"')

expect "runtime user (gosu privilege drop)" "retro" \
    "$(entrypoint_output "${USER_ENV[@]}" "${IMAGE_NAME}" whoami)"
expect "XDG_RUNTIME_DIR mode" "700" \
    "$(entrypoint_output "${USER_ENV[@]}" "${IMAGE_NAME}" stat -c %a /run/user/1000)"
expect "XDG_RUNTIME_DIR default" "/run/user/1000" \
    "$(entrypoint_output "${USER_ENV[@]}" "${IMAGE_NAME}" "${PRINT_XDG[@]}")"
expect "legacy XDG_RUNTIME_DIR=/tmp/.X11-unix normalized" "/run/user/1000" \
    "$(entrypoint_output "${USER_ENV[@]}" -e XDG_RUNTIME_DIR=/tmp/.X11-unix "${IMAGE_NAME}" "${PRINT_XDG[@]}")"
expect "/tmp/.X11-unix mode with separate XDG_RUNTIME_DIR" "1777" \
    "$(entrypoint_output "${USER_ENV[@]}" -e XDG_RUNTIME_DIR=/tmp/runtime-test "${IMAGE_NAME}" stat -c %a /tmp/.X11-unix)"
# The X11 socket dir is shared infrastructure and must be prepared even for root
# containers, which skip runtime-user creation.
expect "/tmp/.X11-unix mode with PUID=0" "1777" \
    "$(entrypoint_output -e PUID=0 -e PGID=0 "${IMAGE_NAME}" stat -c %a /tmp/.X11-unix)"

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "All base runtime checks passed"
exit 0
