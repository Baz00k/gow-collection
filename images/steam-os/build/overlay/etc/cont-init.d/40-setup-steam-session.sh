#!/bin/bash
set -euo pipefail

# shellcheck source=/dev/null
source /opt/gow/logging.sh

STEAM_STARTUP_FLAGS="${STEAM_STARTUP_FLAGS:--gamepadui -steamos3 -steampal -steamdeck}"

export STEAM_STARTUP_FLAGS
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
export HOMETEST_DESKTOP=1
export HOMETEST_DESKTOP_SESSION=plasma
export SRT_URLOPEN_PREFER_STEAM=1
export QT_IM_MODULE=steam
export GTK_IM_MODULE=Steam
export WINEDLLOVERRIDES=dxgi=n
export STEAM_USE_MANGOAPP=1
export STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1
export STEAM_MANGOAPP_PRESETS_SUPPORTED=1
export STEAM_USE_DYNAMIC_VRS=1
export STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT=1
export STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1

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

RADV_FORCE_VRS_CONFIG_FILE=$(mktemp /tmp/radv_vrs.XXXXXXXX)
echo "1x1" > "${RADV_FORCE_VRS_CONFIG_FILE}"
chown "${PUID}:${PGID}" "${RADV_FORCE_VRS_CONFIG_FILE}" 2>/dev/null || true
export RADV_FORCE_VRS_CONFIG_FILE

log_info "SteamOS gamescope integration mode enabled"
log_info "Steam startup flags: ${STEAM_STARTUP_FLAGS}"
log_info "SteamOS desktop session: ${HOMETEST_DESKTOP_SESSION}"
