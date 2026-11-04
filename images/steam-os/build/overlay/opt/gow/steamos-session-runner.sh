#!/bin/bash
set -euo pipefail

# shellcheck source=/dev/null
source /opt/gow/logging.sh
# shellcheck source=/dev/null
source /opt/gow/gamescope-lib.sh

SESSION="${1:-gamescope}"

append_steam_gamescope_args() {
    local -n args_ref="$1"

    # Like SteamOS: the Steam UI gets one Xwayland and games get another
    # (STEAM_GAME_DISPLAY_0). GAMESCOPE_EXTRA_ARGS comes later and can
    # override it with --xwayland-count 1.
    args_ref+=(--xwayland-count 2)

    # Nested gamescope only sends relative mouse motion while a game locks the
    # pointer itself. Otherwise games that read raw input (Wine's included) get
    # absolute positions as motion: menus stick and the camera spins.
    if GAMESCOPE_FORCE_GRAB_CURSOR="${GAMESCOPE_FORCE_GRAB_CURSOR:-on}" \
        gamescope_env_flag_enabled GAMESCOPE_FORCE_GRAB_CURSOR; then
        args_ref+=(--force-grab-cursor)
    fi

    if gamescope_env_flag_enabled GAMESCOPE_FORCE_WINDOWS_FULLSCREEN; then
        args_ref+=(--force-windows-fullscreen)
    fi
}

claim_gamescope_stats_session() {
    local tmpdir stats sessionlink lockfile

    tmpdir="$(mktemp -p "${XDG_RUNTIME_DIR}" -d -t gamescope.XXXXXXX)"
    stats="${tmpdir}/stats.pipe"
    mkfifo -- "${stats}"
    export GAMESCOPE_STATS="${stats}"

    # fd 9 holds the lock for as long as the exec'd session runs.
    sessionlink="${XDG_RUNTIME_DIR}/gamescope-stats"
    lockfile="${sessionlink}.lck"
    exec 9>"${lockfile}"
    if flock -n 9 && rm -f "${sessionlink}" && ln -sf "${tmpdir}" "${sessionlink}"; then
        log_info "Claimed global gamescope stats session at ${sessionlink}"
    else
        log_warn "Could not claim global gamescope stats session"
    fi
}

# Steam runs as gamescope's primary child: gamescope hands it DISPLAY, the
# Steam integration environment, and ENABLE_GAMESCOPE_WSI, and the session
# ends when either of them exits.
start_gamescope_session() {
    local -a gamescope_args=()
    local -a steam_args=()

    read -r -a steam_args <<< "${STEAM_STARTUP_FLAGS:--gamepadui -steamos3 -steampal -steamdeck}"
    log_info "Steam startup flags: ${steam_args[*]}"

    gamescope_require_runtime_dir
    gamescope_append_base_args gamescope_args
    append_steam_gamescope_args gamescope_args
    gamescope_append_extra_args gamescope_args

    claim_gamescope_stats_session

    # shellcheck source=/dev/null
    source /opt/gow/steamos-gaming-env.sh
    steamos_export_gaming_env

    log_info "Starting gamescope with Steam"
    exec dbus-run-session -- /usr/bin/gamescope "${gamescope_args[@]}" \
        -e --mangoapp -T "${GAMESCOPE_STATS}" \
        -- /opt/gow/steam-session.sh "${steam_args[@]}"
}

case "${SESSION}" in
    gamescope)
        start_gamescope_session
        ;;
    plasma)
        exec /opt/gow/steamos-plasma-session.sh
        ;;
    *)
        log_error "Unknown SteamOS session: ${SESSION}"
        exit 1
        ;;
esac
