#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

SESSION_CMD_FIFO="${XDG_RUNTIME_DIR}/gow-steamos-session.cmd"
SESSION_CMD_FD=8
CURRENT_SESSION=""
SESSION_PID=""
SESSION_PGID=""
NEXT_SESSION="${STEAMOS_SESSION:-gamescope}"
STOP_REQUESTED=0

normalize_session() {
    case "${1:-gamescope}" in
        steam|gamescope|gamepad|gaming)
            echo "gamescope"
            ;;
        plasma|desktop|kde)
            echo "plasma"
            ;;
        *)
            log_warn "Unknown SteamOS session '${1}', falling back to gamescope"
            echo "gamescope"
            ;;
    esac
}

prepare_control_fifo() {
    mkdir -p "${XDG_RUNTIME_DIR}"
    rm -f "${SESSION_CMD_FIFO}"
    mkfifo "${SESSION_CMD_FIFO}"
    chmod 600 "${SESSION_CMD_FIFO}"
    exec {SESSION_CMD_FD}<>"${SESSION_CMD_FIFO}"
    export GOW_STEAMOS_SESSION_FIFO="${SESSION_CMD_FIFO}"
}

launch_session() {
    local session="$1"

    CURRENT_SESSION="${session}"
    log_info "Launching SteamOS session: ${CURRENT_SESSION}"

    setsid /opt/gow/steamos-session-runner.sh "${CURRENT_SESSION}" &

    SESSION_PID="$!"
    SESSION_PGID="${SESSION_PID}"
}

stop_session() {
    if [[ -z "${SESSION_PID}" ]] || ! kill -0 "${SESSION_PID}" 2>/dev/null; then
        return 0
    fi

    log_info "Stopping SteamOS session: ${CURRENT_SESSION}"

    if [[ "${CURRENT_SESSION}" == "gamescope" ]]; then
        /usr/bin/steam -shutdown >/dev/null 2>&1 || true
    fi

    kill -TERM -- "-${SESSION_PGID}" 2>/dev/null || true

    for _ in {1..20}; do
        if ! kill -0 "${SESSION_PID}" 2>/dev/null; then
            wait "${SESSION_PID}" 2>/dev/null || true
            return 0
        fi
        sleep 0.25
    done

    log_warn "Session ${CURRENT_SESSION} did not stop cleanly; forcing shutdown"
    kill -KILL -- "-${SESSION_PGID}" 2>/dev/null || true
    wait "${SESSION_PID}" 2>/dev/null || true
}

read_switch_request() {
    local requested

    if ! read -r -t 0.25 -u "${SESSION_CMD_FD}" requested; then
        return 1
    fi

    NEXT_SESSION="$(normalize_session "${requested}")"
    log_info "Requested SteamOS session switch: ${NEXT_SESSION}"
    return 0
}

cleanup() {
    STOP_REQUESTED=1
    stop_session
    exec {SESSION_CMD_FD}>&- || true
    rm -f "${SESSION_CMD_FIFO}"
}

trap cleanup EXIT INT TERM

prepare_control_fifo
NEXT_SESSION="$(normalize_session "${NEXT_SESSION}")"

while [[ "${STOP_REQUESTED}" -eq 0 ]]; do
    launch_session "${NEXT_SESSION}"

    while kill -0 "${SESSION_PID}" 2>/dev/null; do
        if read_switch_request; then
            stop_session
            SESSION_PID=""
            SESSION_PGID=""
            break
        fi
    done

    if [[ -z "${SESSION_PID}" ]]; then
        continue
    fi

    if kill -0 "${SESSION_PID}" 2>/dev/null; then
        continue
    fi

    wait "${SESSION_PID}" 2>/dev/null || true
    SESSION_PID=""
    SESSION_PGID=""
    STOP_REQUESTED=1
done
