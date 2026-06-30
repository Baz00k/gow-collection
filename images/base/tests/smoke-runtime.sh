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

# Files that make up the shared runtime contract.
REQUIRED_EXEC=(
    /opt/gow/entrypoint.sh
    /opt/gow/logging.sh
    /opt/gow/gamescope-lib.sh
    /opt/gow/launch-gamescope.sh
    /opt/gow/apply-performance-tuning.sh
    /etc/cont-init.d/10-setup-user.sh
    /etc/cont-init.d/20-setup-devices.sh
    /etc/cont-init.d/30-nvidia.sh
    /usr/bin/bwrap
    /usr/bin/fusermount
    /usr/bin/fusermount3
    /usr/bin/gamescope
    /usr/bin/gosu
)

for f in "${REQUIRED_EXEC[@]}"; do
    if ! docker exec "${CONTAINER_NAME}" test -f "$f"; then
        echo "${f}: MISSING" >> "${EVIDENCE_FILE}"
        fail "missing ${f}"
    fi
    if ! docker exec "${CONTAINER_NAME}" test -x "$f"; then
        echo "${f}: NOT EXECUTABLE" >> "${EVIDENCE_FILE}"
        fail "not executable ${f}"
    fi
    echo "${f}: ok (executable)" >> "${EVIDENCE_FILE}"
done

# Entrypoint runtime user convention.
RUNTIME_USER=$(docker exec "${CONTAINER_NAME}" awk -F'"' '/^UNAME=/{print $2}' /opt/gow/entrypoint.sh)
echo "Entrypoint UNAME default: ${RUNTIME_USER}" >> "${EVIDENCE_FILE}"
[[ "${RUNTIME_USER}" == *retro* ]] || fail "runtime user default not retro"

# XDG fallback is a private per-user runtime dir, not the global X11 socket dir.
if ! docker exec "${CONTAINER_NAME}" grep -qF 'XDG_RUNTIME_DIR="/run/user/${PUID}"' /opt/gow/entrypoint.sh; then
    fail "XDG_RUNTIME_DIR fallback missing"
fi

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

# logging helpers are sourceable and define log_info.
if ! docker exec "${CONTAINER_NAME}" bash -c 'source /opt/gow/logging.sh && type log_info >/dev/null'; then
    fail "logging.sh does not provide log_info"
fi

# Gamescope helpers are sourceable and provide the shared session contract.
if ! docker exec "${CONTAINER_NAME}" bash -c 'source /opt/gow/gamescope-lib.sh && type gamescope_append_base_args >/dev/null'; then
    fail "gamescope-lib.sh does not provide gamescope_append_base_args"
fi

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

if ! docker exec "${CONTAINER_NAME}" bash -n /opt/gow/launch-gamescope.sh; then
    fail "launch-gamescope.sh has a syntax error"
fi

# Runtime user creation actually works end-to-end (run entrypoint with a noop cmd).
# The entrypoint logs to stdout before exec'ing the command, so take the last
# non-empty line as the command's own output.
log_info "Verifying gosu privilege-drop via entrypoint..."
WHOAMI=$(docker run --rm -e PUID=1000 -e PGID=1000 "${IMAGE_NAME}" whoami 2>/dev/null \
    | grep -v '\[INFO\]' | grep -v '\[WARN\]' | sed '/^$/d' | tail -1 || true)
echo "entrypoint 'whoami' as PUID=1000: ${WHOAMI}" >> "${EVIDENCE_FILE}"
[[ "${WHOAMI}" == "retro" ]] || fail "entrypoint did not drop to retro user (got '${WHOAMI}')"

RUNTIME_DIR_MODE=$(docker run --rm -e PUID=1000 -e PGID=1000 "${IMAGE_NAME}" stat -c %a /run/user/1000 2>/dev/null \
    | grep -v '\[INFO\]' | grep -v '\[WARN\]' | sed '/^$/d' | tail -1 || true)
echo "entrypoint XDG_RUNTIME_DIR mode: ${RUNTIME_DIR_MODE}" >> "${EVIDENCE_FILE}"
[[ "${RUNTIME_DIR_MODE}" == "700" ]] || fail "XDG_RUNTIME_DIR /run/user/1000 must be mode 700 (got '${RUNTIME_DIR_MODE}')"

RUNTIME_DIR_ENV=$(docker run --rm -e PUID=1000 -e PGID=1000 "${IMAGE_NAME}" bash -c 'printf "%s" "${XDG_RUNTIME_DIR}"' 2>/dev/null \
    | grep -v '\[INFO\]' | grep -v '\[WARN\]' | sed '/^$/d' | tail -1 || true)
echo "entrypoint XDG_RUNTIME_DIR value: ${RUNTIME_DIR_ENV}" >> "${EVIDENCE_FILE}"
[[ "${RUNTIME_DIR_ENV}" == "/run/user/1000" ]] || fail "XDG_RUNTIME_DIR default must be /run/user/1000 (got '${RUNTIME_DIR_ENV}')"

X11_SOCKET_MODE=$(docker run --rm -e PUID=1000 -e PGID=1000 -e XDG_RUNTIME_DIR=/tmp/runtime-test "${IMAGE_NAME}" stat -c %a /tmp/.X11-unix 2>/dev/null \
    | grep -v '\[INFO\]' | grep -v '\[WARN\]' | sed '/^$/d' | tail -1 || true)
echo "entrypoint /tmp/.X11-unix mode with separate XDG_RUNTIME_DIR: ${X11_SOCKET_MODE}" >> "${EVIDENCE_FILE}"
[[ "${X11_SOCKET_MODE}" == "1777" ]] || fail "/tmp/.X11-unix must be mode 1777 even when XDG_RUNTIME_DIR differs (got '${X11_SOCKET_MODE}')"

LEGACY_RUNTIME_DIR_ENV=$(docker run --rm -e PUID=1000 -e PGID=1000 -e XDG_RUNTIME_DIR=/tmp/.X11-unix "${IMAGE_NAME}" bash -c 'printf "%s" "${XDG_RUNTIME_DIR}"' 2>/dev/null \
    | grep -v '\[INFO\]' | grep -v '\[WARN\]' | sed '/^$/d' | tail -1 || true)
echo "entrypoint legacy XDG_RUNTIME_DIR override result: ${LEGACY_RUNTIME_DIR_ENV}" >> "${EVIDENCE_FILE}"
[[ "${LEGACY_RUNTIME_DIR_ENV}" == "/run/user/1000" ]] || fail "legacy XDG_RUNTIME_DIR=/tmp/.X11-unix must be normalized (got '${LEGACY_RUNTIME_DIR_ENV}')"

# The X11 socket dir is shared infrastructure and must be prepared even for root
# containers, which skip runtime-user creation.
ROOT_X11_SOCKET_MODE=$(docker run --rm -e PUID=0 -e PGID=0 "${IMAGE_NAME}" stat -c %a /tmp/.X11-unix 2>/dev/null \
    | grep -v '\[INFO\]' | grep -v '\[WARN\]' | sed '/^$/d' | tail -1 || true)
echo "entrypoint /tmp/.X11-unix mode with PUID=0: ${ROOT_X11_SOCKET_MODE}" >> "${EVIDENCE_FILE}"
[[ "${ROOT_X11_SOCKET_MODE}" == "1777" ]] || fail "/tmp/.X11-unix must be mode 1777 for root containers (got '${ROOT_X11_SOCKET_MODE}')"

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "All base runtime checks passed"
exit 0
