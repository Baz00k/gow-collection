#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh
source /opt/gow/gamescope-lib.sh

log_info "Steam startup.sh"

export HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"
mkdir -p "${HOME}/.steam/ubuntu12_32/steam-runtime"

STEAM_STARTUP_FLAGS="${STEAM_STARTUP_FLAGS:--bigpicture}"
GAMESCOPE_STEAM_MODE="${GAMESCOPE_STEAM_MODE:-off}"

read -r -a STEAM_ARGS <<< "${STEAM_STARTUP_FLAGS}"

start_ibus() {
    /usr/bin/ibus-daemon -d -r --panel=disable --emoji-extension=disable
}

append_steam_gamescope_args() {
    local -n args_ref="$1"

    if gamescope_env_flag_enabled GAMESCOPE_FORCE_WINDOWS_FULLSCREEN; then
        args_ref+=(--force-windows-fullscreen)
    fi
}

start_steam_mode_gamescope() {
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
        unset WAYLAND_DISPLAY
        log_info "Gamescope started in Steam integration mode: DISPLAY=${DISPLAY}"
        return 0
    fi

    log_error "gamescope did not become ready for Steam integration mode"
    exit 1
}

start_standard_steam() {
    local -a extra_args=()

    append_steam_gamescope_args extra_args
    GAMESCOPE_EXTRA_ARGS="${extra_args[*]}" exec /opt/gow/launch-gamescope.sh \
        /opt/gow/steam-session.sh "${STEAM_ARGS[@]}"
}

log_info "Gamescope Steam integration mode: ${GAMESCOPE_STEAM_MODE}"

case "${GAMESCOPE_STEAM_MODE}" in
    1|true|yes|on)
        start_steam_mode_gamescope
        start_ibus
        exec dbus-run-session -- /usr/bin/steam "${STEAM_ARGS[@]}"
        ;;
    0|false|no|off)
        start_standard_steam
        ;;
    *)
        log_error "GAMESCOPE_STEAM_MODE: unknown value '${GAMESCOPE_STEAM_MODE}'"
        exit 1
        ;;
esac
