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

session_group_alive() {
    [[ -n "${SESSION_PGID}" ]] && kill -0 -- "-${SESSION_PGID}" 2>/dev/null
}

wait_for_session_group_exit() {
    local timeout_ticks="$1" tick

    for ((tick = 0; tick < timeout_ticks; tick++)); do
        session_group_alive || return 0
        sleep 0.25
    done

    ! session_group_alive
}

# Ask Steam to quit on its own first, so it can sync and save. Bounded so a
# hung Steam cannot block a session switch.
request_steam_shutdown() {
    timeout -k 2 10 /usr/bin/steam -shutdown >/dev/null 2>&1 || true
}

terminate_session_group() {
    session_group_alive || return 0

    kill -TERM -- "-${SESSION_PGID}" 2>/dev/null || true
    if ! wait_for_session_group_exit 20; then
        log_warn "Session ${CURRENT_SESSION} did not stop cleanly; forcing shutdown"
        kill -KILL -- "-${SESSION_PGID}" 2>/dev/null || true
    fi
}

stop_session() {
    if ! session_group_alive; then
        return 0
    fi

    log_info "Stopping SteamOS session: ${CURRENT_SESSION}"

    if [[ "${CURRENT_SESSION}" == "gamescope" ]] && kill -0 "${SESSION_PID}" 2>/dev/null; then
        request_steam_shutdown
        wait_for_session_group_exit 40 || true
    fi

    terminate_session_group
    wait "${SESSION_PID}" 2>/dev/null || true
}

# The session leader exited on its own; stop anything it left behind in its
# process group before forgetting the group.
reap_finished_session() {
    wait "${SESSION_PID}" 2>/dev/null || true
    if session_group_alive; then
        log_warn "Session ${CURRENT_SESSION} exited with processes left behind; stopping them"
        terminate_session_group
    fi
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

    reap_finished_session
    SESSION_PID=""
    SESSION_PGID=""
    STOP_REQUESTED=1
done
