#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh
source /opt/gow/gamescope-lib.sh

SESSION="${1:-gamescope}"
STEAM_STARTUP_FLAGS="${STEAM_STARTUP_FLAGS:--gamepadui}"
read -r -a STEAM_ARGS <<< "${STEAM_STARTUP_FLAGS}"

start_ibus() {
    /usr/bin/ibus-daemon -d -r --panel=disable --emoji-extension=disable || true
}

append_steam_gamescope_args() {
    local -n args_ref="$1"

    if gamescope_env_flag_enabled GAMESCOPE_FORCE_WINDOWS_FULLSCREEN; then
        args_ref+=(--force-windows-fullscreen)
    fi
}

start_gamescope_compositor() {
    local -a gamescope_args=()
    local tmpdir socket stats sessionlink lockfile

    gamescope_require_runtime_dir
    gamescope_append_base_args gamescope_args
    append_steam_gamescope_args gamescope_args

    tmpdir="$(mktemp -p "${XDG_RUNTIME_DIR}" -d -t gamescope.XXXXXXX)"
    socket="${tmpdir}/startup.socket"
    stats="${tmpdir}/stats.pipe"

    export GAMESCOPE_STATS="${stats}"
    mkfifo -- "${stats}" "${socket}"

    sessionlink="${XDG_RUNTIME_DIR}/gamescope-stats"
    lockfile="${sessionlink}.lck"
    exec 9>"${lockfile}"
    if flock -n 9 && rm -f "${sessionlink}" && ln -sf "${tmpdir}" "${sessionlink}"; then
        log_info "Claimed global gamescope stats session at ${sessionlink}"
    else
        log_warn "Could not claim global gamescope stats session"
    fi

    /usr/bin/gamescope "${gamescope_args[@]}" -e --mangoapp -R "${socket}" -T "${stats}" &

    if read -r -t 5 DISPLAY GAMESCOPE_WAYLAND_DISPLAY <> "${socket}"; then
        export DISPLAY GAMESCOPE_WAYLAND_DISPLAY
        log_info "Gamescope started for Steam session: DISPLAY=${DISPLAY}"
        return 0
    fi

    log_error "gamescope did not become ready for Steam session"
    exit 1
}

case "${SESSION}" in
    gamescope)
        start_gamescope_compositor
        start_ibus
        unset WAYLAND_DISPLAY
        exec dbus-run-session -- /usr/bin/steam "${STEAM_ARGS[@]}"
        ;;
    plasma)
        exec /opt/gow/steamos-plasma-session.sh
        ;;
    *)
        log_error "Unknown SteamOS session: ${SESSION}"
        exit 1
        ;;
esac
