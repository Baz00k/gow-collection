#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

STEAM_STARTUP_FLAGS="${STEAM_STARTUP_FLAGS:--bigpicture}"
GAMESCOPE_STEAM_MODE="${GAMESCOPE_STEAM_MODE:-off}"

export STEAM_STARTUP_FLAGS
export GAMESCOPE_STEAM_MODE
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
export SRT_URLOPEN_PREFER_STEAM=1
export QT_IM_MODULE=steam
export GTK_IM_MODULE=Steam
export WINEDLLOVERRIDES=dxgi=n

if [ -z "${MANGOHUD_CONFIGFILE:-}" ]; then
    MANGOHUD_CONFIGFILE=$(mktemp /tmp/mangohud.XXXXXXXX)
    cat > "${MANGOHUD_CONFIGFILE}" <<'EOF'
fps
gpu_stats
cpu_stats
frametime
position=top-right
no_display
EOF
    chown "${PUID}:${PGID}" "${MANGOHUD_CONFIGFILE}" 2>/dev/null || true
    export MANGOHUD_CONFIGFILE
    log_info "MangoHud config: ${MANGOHUD_CONFIGFILE}"
else
    export MANGOHUD_CONFIGFILE
    log_info "Using provided MangoHud config: ${MANGOHUD_CONFIGFILE}"
fi

if [ "${GAMESCOPE_STEAM_MODE}" = "on" ]; then
    export STEAM_USE_MANGOAPP=1
    export STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1
    export STEAM_MANGOAPP_PRESETS_SUPPORTED=1
    export STEAM_USE_DYNAMIC_VRS=1
    export STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT=1
    export STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1

    RADV_FORCE_VRS_CONFIG_FILE=$(mktemp /tmp/radv_vrs.XXXXXXXX)
    echo "1x1" > "${RADV_FORCE_VRS_CONFIG_FILE}"
    chown "${PUID}:${PGID}" "${RADV_FORCE_VRS_CONFIG_FILE}" 2>/dev/null || true
    export RADV_FORCE_VRS_CONFIG_FILE
else
    export MANGOHUD=1
fi

log_info "Gamescope Steam integration mode: ${GAMESCOPE_STEAM_MODE}"
