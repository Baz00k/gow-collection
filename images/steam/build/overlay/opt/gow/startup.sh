#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

log_info "Steam startup.sh"

# Ensure HOME is set (runuser may not set it on all distros)
export HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"

# Apply performance tunings (sysctl) where container capabilities permit
# launch-comp.sh exits 0 with graceful degradation if permissions insufficient
/opt/gow/launch-comp.sh || true

# Recursively creating Steam necessary folders
# https://github.com/ValveSoftware/steam-for-linux/issues/6492
mkdir -p "$HOME/.steam/ubuntu12_32/steam-runtime"

# Use big picture mode by default
STEAM_STARTUP_FLAGS=${STEAM_STARTUP_FLAGS:-"-bigpicture"}

export MANGOHUD_CONFIGFILE=$(mktemp /tmp/mangohud.XXXXXXXX)
mkdir -p "$(dirname "$MANGOHUD_CONFIGFILE")"
cat > "$MANGOHUD_CONFIGFILE" << 'MANGOHUD_EOF'
fps
gpu_stats
cpu_stats
frametime
position=top-right
no_display
MANGOHUD_EOF
log_info "MangoHud config: ${MANGOHUD_CONFIGFILE}"

# =============================================================================
# Gamescope Steam integration mode
# =============================================================================
# GAMESCOPE_STEAM_MODE controls whether gamescope runs with Steam integration
# (-e flag), which makes Steam enter SteamOS/GamepadUI mode:
#   - "on"  → SteamOS-like experience: MangoApp overlay, VRS, fancy scaling,
#              power management UI, "Switch to desktop" button
#   - "off" → Standard Big Picture: normal Steam UI, "Exit Big Picture" button,
#              ability to switch to desktop mode (default)
GAMESCOPE_STEAM_MODE="${GAMESCOPE_STEAM_MODE:-off}"
log_info "Gamescope Steam integration mode: ${GAMESCOPE_STEAM_MODE}"

# Some game fixes taken from the Steam Deck
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0

# Have SteamRT's xdg-open send http:// and https:// URLs to Steam
export SRT_URLOPEN_PREFER_STEAM=1

# Set input method modules for Qt/GTK that will show the Steam keyboard
export QT_IM_MODULE=steam
export GTK_IM_MODULE=Steam

# To expose vram info from radv
export WINEDLLOVERRIDES=dxgi=n

# =============================================================================
# SteamOS integration features (only in Steam mode)
# =============================================================================
if [[ "${GAMESCOPE_STEAM_MODE}" == "on" ]]; then
    export STEAM_USE_MANGOAPP=1
    export STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1
    export STEAM_MANGOAPP_PRESETS_SUPPORTED=1
    export STEAM_USE_DYNAMIC_VRS=1
    export STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT=1
    export STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1

    export RADV_FORCE_VRS_CONFIG_FILE=$(mktemp /tmp/radv_vrs.XXXXXXXX)
    mkdir -p "$(dirname "$RADV_FORCE_VRS_CONFIG_FILE")"
    echo "1x1" > "$RADV_FORCE_VRS_CONFIG_FILE"
else
    export MANGOHUD=1
fi

# =============================================================================
# Gamescope launch
# =============================================================================
if [[ -z "${XDG_RUNTIME_DIR+x}" ]]; then
    log_error "XDG_RUNTIME_DIR is not set — cannot start gamescope"
    exit 1
fi

GAMESCOPE_WIDTH=${GAMESCOPE_WIDTH:-1920}
GAMESCOPE_HEIGHT=${GAMESCOPE_HEIGHT:-1080}
GAMESCOPE_GAME_WIDTH=${GAMESCOPE_GAME_WIDTH:-${GAMESCOPE_WIDTH}}
GAMESCOPE_GAME_HEIGHT=${GAMESCOPE_GAME_HEIGHT:-${GAMESCOPE_HEIGHT}}
GAMESCOPE_REFRESH=${GAMESCOPE_REFRESH:-60}
GAMESCOPE_MODE=${GAMESCOPE_MODE:-"-b"}
GAMESCOPE_FORCE_WINDOWS_FULLSCREEN="${GAMESCOPE_FORCE_WINDOWS_FULLSCREEN:-off}"

log_info "Display environment: WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"
if [ "${GOW_DEBUG_LEVEL}" -ge 1 ]; then
    log_debug "Debug mode enabled"
    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        log_debug "Wayland socket: $(ls -la "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" 2>&1 || echo 'not found')"
    fi
    log_debug "GPU devices: $(ls /dev/nvidia* /dev/dri/* 2>/dev/null | tr '\n' ' ' || echo 'NONE')"
fi
if [ "${GOW_DEBUG_LEVEL}" -ge 2 ]; then
    log_verbose "NVIDIA env: LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-unset} VK_DRIVER_FILES=${VK_DRIVER_FILES:-unset}"
fi

log_steam_state() {
    local steam_link="${HOME}/.steam/steam"
    local steam_data="${HOME}/.local/share/Steam"

    if [ "${GOW_DEBUG_LEVEL}" -lt 1 ]; then
        return 0
    fi

    log_debug "Steam home: HOME=${HOME}"
    log_debug "Steam data path: ${steam_data}"

    if [ -L "${steam_link}" ]; then
        log_debug "Steam symlink: ${steam_link} -> $(readlink "${steam_link}")"
    elif [ -d "${steam_link}" ]; then
        log_debug "Steam path ${steam_link} is a directory, not a symlink; this usually means legacy/upstream Steam state"
    else
        log_debug "Steam path ${steam_link} does not exist yet"
    fi

    if [ -d "${steam_data}" ]; then
        log_debug "Steam data ownership: $(stat -c '%U:%G %a' "${steam_data}" 2>/dev/null || echo 'unknown')"
    else
        log_debug "Steam data directory does not exist yet"
    fi
}

log_steam_exit_diagnostics() {
    local steam_exit_code="$1"
    log_warn "Steam process returned with code ${steam_exit_code}"
    if [ -n "${STEAM_STARTUP_FLAGS}" ]; then
        log_debug "Steam startup flags are set; values omitted from diagnostics"
    else
        log_debug "Steam startup flags are empty"
    fi
    log_steam_state

    local steam_processes
    steam_processes=$(pgrep -l -u "$(id -u)" -f 'steam|steamwebhelper' 2>/dev/null || true)
    if [ -n "${steam_processes}" ]; then
        log_debug "Steam-related processes are still running after launcher exit (PID and process name only):"
        printf '%s\n' "${steam_processes}"
    else
        log_debug "No Steam-related processes remain after launcher exit"
    fi

    local lock_matches
    if [ "${GOW_DEBUG_LEVEL}" -ge 2 ]; then
        lock_matches=$(find "${HOME}/.steam" "${HOME}/.local/share/Steam" -maxdepth 3 \
            \( -iname '*lock*' -o -iname 'steam.pid' -o -iname '.crash' \) \
            -print 2>/dev/null || true)
        if [ -n "${lock_matches}" ]; then
            log_verbose "Potential Steam lock/state files:"
            printf '%s\n' "${lock_matches}"
        fi

        if [ -d "${HOME}/.local/share/Steam/logs" ]; then
            log_verbose "Recent Steam log files:"
            find "${HOME}/.local/share/Steam/logs" -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort | tail -n 10 || true
        fi
    fi
}

GAMESCOPE_EXTRA_ARGS=""

case "${GAMESCOPE_FORCE_WINDOWS_FULLSCREEN,,}" in
    1|true|yes|on)
        GAMESCOPE_EXTRA_ARGS="${GAMESCOPE_EXTRA_ARGS} --force-windows-fullscreen"
        ;;
    0|false|no|off)
        ;;
    *)
        log_warn "GAMESCOPE_FORCE_WINDOWS_FULLSCREEN: unknown value '${GAMESCOPE_FORCE_WINDOWS_FULLSCREEN}', defaulting to off"
        ;;
esac

if [[ "${GAMESCOPE_STEAM_MODE}" == "on" ]]; then
    # Steam integration mode: set up stats pipe and ready socket for MangoApp
    tmpdir="$(mktemp -p "$XDG_RUNTIME_DIR" -d -t gamescope.XXXXXXX)"
    socket="${tmpdir}/startup.socket"
    stats="${tmpdir}/stats.pipe"

    export GAMESCOPE_STATS="$stats"
    mkfifo -- "$stats"
    mkfifo -- "$socket"

    linkname="gamescope-stats"
    # shellcheck disable=SC2031
    sessionlink="${XDG_RUNTIME_DIR}/${linkname}"
    lockfile="$sessionlink".lck
    exec 9>"$lockfile"
    if flock -n 9 && rm -f "$sessionlink" && ln -sf "$tmpdir" "$sessionlink"; then
        echo >&2 "Claimed global gamescope stats session at \"$sessionlink\""
    else
        echo >&2 "!! Failed to claim global gamescope stats session"
    fi

    # -e enables Steam integration (SteamOS UI, MangoApp, stats pipe)
    GAMESCOPE_EXTRA_ARGS="${GAMESCOPE_EXTRA_ARGS} -e --mangoapp -R $socket -T $stats"
fi

# shellcheck disable=SC2086
VK_LOADER_DEBUG=error /usr/bin/gamescope --backend wayland ${GAMESCOPE_EXTRA_ARGS} \
    ${GAMESCOPE_MODE} \
    -w "${GAMESCOPE_GAME_WIDTH}" -h "${GAMESCOPE_GAME_HEIGHT}" \
    -W "${GAMESCOPE_WIDTH}" -H "${GAMESCOPE_HEIGHT}" -r "${GAMESCOPE_REFRESH}" \
    2>/tmp/gamescope.log &

GAMESCOPE_PID=$!
sleep 0.3
if ! kill -0 "${GAMESCOPE_PID}" 2>/dev/null; then
    log_error "gamescope crashed immediately (PID ${GAMESCOPE_PID})"
    log_error "--- gamescope.log ---"
    cat /tmp/gamescope.log >&2 || true
    log_error "--- end gamescope.log ---"
    if [ "${GOW_DEBUG_LEVEL}" -ge 2 ]; then
        log_debug "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
        log_debug "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"
        log_debug "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-unset}"
        log_debug "VK_DRIVER_FILES=${VK_DRIVER_FILES:-unset}"
        log_debug "Available in XDG_RUNTIME_DIR: $(ls -la "${XDG_RUNTIME_DIR}/" 2>&1 || echo 'dir not found')"
        log_debug "Vulkan ICDs: $(ls /usr/share/vulkan/icd.d/ 2>&1 || echo 'none found')"
        log_debug "NVIDIA ICD content: $(cat /usr/share/vulkan/icd.d/nvidia_icd.json 2>&1 || echo 'not found')"
        log_debug "GPU devices: $(ls -la /dev/nvidia* /dev/dri/* 2>&1 || echo 'NO GPU DEVICES FOUND')"
        log_debug "NVIDIA libs in ldconfig: $(ldconfig -p 2>/dev/null | grep -i nvidia | head -5 || echo 'none')"
        log_debug "NVIDIA /usr/nvidia/lib: $(ls /usr/nvidia/lib/libGLX_nvidia* /usr/nvidia/lib/libnvidia-glcore* 2>&1 | head -5 || echo 'not found')"
    fi
    exit 1
fi

if [[ "${GAMESCOPE_STEAM_MODE}" == "on" ]]; then
    # In Steam mode, read display info from the ready socket
    if read -r -t 3 response_x_display response_wl_display <> "$socket"; then
        export DISPLAY="$response_x_display"
        export GAMESCOPE_WAYLAND_DISPLAY="$response_wl_display"
        unset WAYLAND_DISPLAY
        log_info "Gamescope started (Steam mode): DISPLAY=$DISPLAY"
    else
        log_error "gamescope failed to respond within 3 seconds"
        log_error "--- gamescope.log ---"
        cat /tmp/gamescope.log >&2 || true
        log_error "--- end gamescope.log ---"
        exit 1
    fi
else
    # Without -e, gamescope doesn't use the ready socket protocol.
    # Wait for the X11 socket to appear.
    DISPLAY=":0"
    export DISPLAY
    unset WAYLAND_DISPLAY

    X11_SOCKET="/tmp/.X11-unix/X0"
    RETRIES=0
    MAX_RETRIES=30
    while [ ! -e "${X11_SOCKET}" ]; do
        RETRIES=$((RETRIES + 1))
        if [ "${RETRIES}" -ge "${MAX_RETRIES}" ]; then
            log_error "gamescope X11 socket ${X11_SOCKET} not ready after ${MAX_RETRIES} attempts"
            log_error "--- gamescope.log ---"
            cat /tmp/gamescope.log >&2 || true
            log_error "--- end gamescope.log ---"
            exit 1
        fi
        sleep 0.1
    done
    log_info "Gamescope started (desktop mode): DISPLAY=$DISPLAY"
fi

/usr/bin/ibus-daemon -d -r --panel=disable --emoji-extension=disable

cleanup_on_exit() {
    local steam_exit_code=$?
    if [ "${GOW_DEBUG_LEVEL}" -ge 1 ]; then
        log_steam_exit_diagnostics "${steam_exit_code}" || true
    fi

    log_info "Steam exited with code ${steam_exit_code}, shutting down..."

    if kill -0 "${GAMESCOPE_PID}" 2>/dev/null; then
        log_info "Terminating gamescope (PID ${GAMESCOPE_PID})..."
        kill "${GAMESCOPE_PID}" 2>/dev/null || true
        wait "${GAMESCOPE_PID}" 2>/dev/null || true
    fi

    exit "${steam_exit_code}"
}
trap cleanup_on_exit EXIT

# shellcheck disable=SC2086
dbus-run-session -- /usr/bin/steam ${STEAM_STARTUP_FLAGS}
