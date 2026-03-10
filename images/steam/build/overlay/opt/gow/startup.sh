#!/bin/bash
set -euo pipefail

# Inline GoW utility functions (no base-app dependency)
gow_log() { echo "$(date +"[%Y-%m-%d %H:%M:%S]") $*"; }
gow_error() { echo -e "\033[0;31m[ERROR]\033[0m $*"; }

gow_log "Steam startup.sh"

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
gow_log "Gamescope Steam integration mode: ${GAMESCOPE_STEAM_MODE}"

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
    # Enable Mangoapp (requires gamescope stats pipe)
    export STEAM_USE_MANGOAPP=1
    export MANGOHUD_CONFIGFILE=$(mktemp /tmp/mangohud.XXXXXXXX)
    export STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1

    # Enable Variable Rate Shading
    # Note: this only works on gallium drivers and with new enough mesa
    export STEAM_USE_DYNAMIC_VRS=1
    export RADV_FORCE_VRS_CONFIG_FILE=$(mktemp /tmp/radv_vrs.XXXXXXXX)

    # Initially write no_display to our config file
    # so we don't get mangoapp showing up before Steam initializes
    mkdir -p "$(dirname "$MANGOHUD_CONFIGFILE")"
    echo "position=top-right" > "$MANGOHUD_CONFIGFILE"
    echo "no_display" >> "$MANGOHUD_CONFIGFILE"

    # Prepare our initial VRS config file for dynamic VRS in Mesa
    mkdir -p "$(dirname "$RADV_FORCE_VRS_CONFIG_FILE")"
    echo "1x1" > "$RADV_FORCE_VRS_CONFIG_FILE"

    # Scaling support
    export STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT=1

    export STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1
fi

# =============================================================================
# Gamescope launch
# =============================================================================
if [[ -z "${XDG_RUNTIME_DIR+x}" ]]; then
    gow_error "XDG_RUNTIME_DIR is not set — cannot start gamescope"
    exit 1
fi

GAMESCOPE_WIDTH=${GAMESCOPE_WIDTH:-1920}
GAMESCOPE_HEIGHT=${GAMESCOPE_HEIGHT:-1080}
GAMESCOPE_REFRESH=${GAMESCOPE_REFRESH:-60}
GAMESCOPE_MODE=${GAMESCOPE_MODE:-"-b"}

gow_log "Display environment: WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    gow_log "Wayland socket: $(ls -la "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" 2>&1 || echo 'not found')"
fi
gow_log "NVIDIA env: LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-unset} VK_DRIVER_FILES=${VK_DRIVER_FILES:-unset}"
gow_log "GPU devices: $(ls /dev/nvidia* /dev/dri/* 2>/dev/null | tr '\n' ' ' || echo 'NONE')"

GAMESCOPE_EXTRA_ARGS=""

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
    GAMESCOPE_EXTRA_ARGS="-e -R $socket -T $stats"
fi

# shellcheck disable=SC2086
VK_LOADER_DEBUG=error /usr/bin/gamescope --backend wayland ${GAMESCOPE_EXTRA_ARGS} \
    ${GAMESCOPE_MODE} \
    -W "${GAMESCOPE_WIDTH}" -H "${GAMESCOPE_HEIGHT}" -r "${GAMESCOPE_REFRESH}" \
    2>/tmp/gamescope.log &

GAMESCOPE_PID=$!
sleep 0.3
if ! kill -0 "${GAMESCOPE_PID}" 2>/dev/null; then
    gow_error "gamescope crashed immediately (PID ${GAMESCOPE_PID})"
    gow_error "--- gamescope.log ---"
    cat /tmp/gamescope.log >&2 || true
    gow_error "--- end gamescope.log ---"
    gow_error "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
    gow_error "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-unset}"
    gow_error "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-unset}"
    gow_error "VK_DRIVER_FILES=${VK_DRIVER_FILES:-unset}"
    gow_error "Available in XDG_RUNTIME_DIR: $(ls -la "${XDG_RUNTIME_DIR}/" 2>&1 || echo 'dir not found')"
    gow_error "Vulkan ICDs: $(ls /usr/share/vulkan/icd.d/ 2>&1 || echo 'none found')"
    gow_error "NVIDIA ICD content: $(cat /usr/share/vulkan/icd.d/nvidia_icd.json 2>&1 || echo 'not found')"
    gow_error "GPU devices: $(ls -la /dev/nvidia* /dev/dri/* 2>&1 || echo 'NO GPU DEVICES FOUND')"
    gow_error "NVIDIA libs in ldconfig: $(ldconfig -p 2>/dev/null | grep -i nvidia | head -5 || echo 'none')"
    gow_error "NVIDIA /usr/nvidia/lib: $(ls /usr/nvidia/lib/libGLX_nvidia* /usr/nvidia/lib/libnvidia-glcore* 2>&1 | head -5 || echo 'not found')"
    exit 1
fi

if [[ "${GAMESCOPE_STEAM_MODE}" == "on" ]]; then
    # In Steam mode, read display info from the ready socket
    if read -r -t 3 response_x_display response_wl_display <> "$socket"; then
        export DISPLAY="$response_x_display"
        export GAMESCOPE_WAYLAND_DISPLAY="$response_wl_display"
        unset WAYLAND_DISPLAY
        gow_log "Gamescope started (Steam mode): DISPLAY=$DISPLAY"
    else
        gow_error "gamescope failed to respond within 3 seconds"
        gow_error "--- gamescope.log ---"
        cat /tmp/gamescope.log >&2 || true
        gow_error "--- end gamescope.log ---"
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
            gow_error "gamescope X11 socket ${X11_SOCKET} not ready after ${MAX_RETRIES} attempts"
            gow_error "--- gamescope.log ---"
            cat /tmp/gamescope.log >&2 || true
            gow_error "--- end gamescope.log ---"
            exit 1
        fi
        sleep 0.1
    done
    gow_log "Gamescope started (desktop mode): DISPLAY=$DISPLAY"
fi

/usr/bin/ibus-daemon -d -r --panel=disable --emoji-extension=disable

if [[ "${GAMESCOPE_STEAM_MODE}" == "on" ]]; then
    mangoapp &
fi

# shellcheck disable=SC2086
dbus-run-session -- /usr/bin/steam ${STEAM_STARTUP_FLAGS}
