#!/bin/bash
# Environment for the gamescope gaming session only. Sourced by
# steamos-session-runner.sh so none of it leaks into the Plasma session.
#
# gamescope -e already gives its children the STEAM_GAMESCOPE_*, mangoapp and
# SDL settings it supports (gamescope src/main.cpp UpdateCompatEnvVars), so only
# settings gamescope does not provide belong here.

# shellcheck source=/dev/null
source /opt/gow/logging.sh

DRI_DEVICE_DIR="${DRI_DEVICE_DIR:-/dev/dri}"
SYSFS_DRM_DIR="${SYSFS_DRM_DIR:-/sys/class/drm}"

# Conservative check that games will render through Mesa RADV: every usable
# render node is driven by amdgpu and no Vulkan ICD override selects another
# driver. Mixed or unknown setups return false.
steamos_radv_is_game_driver() {
    local var value icd node driver
    local -a icds=()
    local found=0

    for var in VK_DRIVER_FILES VK_ICD_FILENAMES; do
        value="${!var:-}"
        [[ -n "${value}" ]] || continue
        IFS=: read -r -a icds <<< "${value}"
        for icd in "${icds[@]}"; do
            [[ -z "${icd}" || "${icd##*/}" == radeon_icd* ]] || return 1
        done
    done

    if [[ "${AMD_VULKAN_ICD:-}" =~ ^[Aa][Mm][Dd][Vv][Ll][Kk]$ ]]; then
        return 1
    fi

    for node in "${DRI_DEVICE_DIR}"/renderD*; do
        [[ -e "${node}" ]] || continue
        driver="$(readlink "${SYSFS_DRM_DIR}/${node##*/}/device/driver" 2>/dev/null)" || return 1
        [[ "${driver##*/}" == "amdgpu" ]] || return 1
        found=1
    done

    (( found == 1 ))
}

# Steam lowers the shading rate through RADV_FORCE_VRS_CONFIG_FILE when it
# limits the framerate. RADV-only; values the user already set always win.
steamos_setup_dynamic_vrs() {
    local mode="${STEAM_DYNAMIC_VRS:-auto}"

    case "${mode,,}" in
        auto|1|true|yes|on|0|false|no|off)
            ;;
        *)
            log_warn "STEAM_DYNAMIC_VRS: unknown value '${mode}', defaulting to auto"
            mode=auto
            ;;
    esac

    case "${mode,,}" in
        auto)
            if ! steamos_radv_is_game_driver; then
                log_info "Dynamic VRS off: RADV is not the game Vulkan driver (STEAM_DYNAMIC_VRS=auto)"
                return 0
            fi
            ;;
        0|false|no|off)
            log_info "Dynamic VRS disabled by STEAM_DYNAMIC_VRS=${mode}"
            return 0
            ;;
    esac

    # Set-but-empty counts as a user choice too.
    export STEAM_USE_DYNAMIC_VRS="${STEAM_USE_DYNAMIC_VRS-1}"

    # /tmp is shared read-write into Pressure Vessel game containers.
    if [[ ! -v RADV_FORCE_VRS_CONFIG_FILE ]]; then
        RADV_FORCE_VRS_CONFIG_FILE="$(mktemp /tmp/radv_vrs.XXXXXXXX)"
        echo "1x1" > "${RADV_FORCE_VRS_CONFIG_FILE}"
        export RADV_FORCE_VRS_CONFIG_FILE
    fi

    log_info "Dynamic VRS enabled: RADV_FORCE_VRS_CONFIG_FILE=${RADV_FORCE_VRS_CONFIG_FILE}"
}

steamos_setup_mangohud_config() {
    if [[ -n "${MANGOHUD_CONFIGFILE:-}" ]]; then
        export MANGOHUD_CONFIGFILE
        log_info "Using provided MangoHud config: ${MANGOHUD_CONFIGFILE}"
        return 0
    fi

    MANGOHUD_CONFIGFILE="$(mktemp /tmp/mangohud.XXXXXXXX)"
    cat > "${MANGOHUD_CONFIGFILE}" <<'EOF'
fps
gpu_stats
cpu_stats
frametime
position=top-right
no_display
EOF
    export MANGOHUD_CONFIGFILE
    log_info "MangoHud config: ${MANGOHUD_CONFIGFILE}"
}

steamos_export_gaming_env() {
    # Steam's on-screen keyboard as the input method.
    export QT_IM_MODULE=steam
    export GTK_IM_MODULE=Steam
    # Steam's "Switch to Desktop" target.
    export HOMETEST_DESKTOP=1
    export HOMETEST_DESKTOP_SESSION=plasma
    # A user-provided value, even an empty one, replaces the default whole.
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES-dxgi=n}"

    steamos_setup_mangohud_config
    steamos_setup_dynamic_vrs
}
