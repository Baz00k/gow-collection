#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

gamescope_require_runtime_dir() {
    if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
        log_error "XDG_RUNTIME_DIR is not set; cannot start gamescope"
        exit 1
    fi
}

gamescope_append_base_args() {
    local -n args_ref="$1"

    local width="${GAMESCOPE_WIDTH:-1920}"
    local height="${GAMESCOPE_HEIGHT:-1080}"
    local game_width="${GAMESCOPE_GAME_WIDTH:-${width}}"
    local game_height="${GAMESCOPE_GAME_HEIGHT:-${height}}"
    local refresh="${GAMESCOPE_REFRESH:-60}"
    local mode="${GAMESCOPE_MODE:--b}"
    local mode_args=()

    # GAMESCOPE_MODE is intentionally shell-like to match existing image config,
    # for example "-b" or "-f".
    read -r -a mode_args <<< "${mode}"

    args_ref+=(
        --backend wayland
        "${mode_args[@]}"
        -w "${game_width}"
        -h "${game_height}"
        -W "${width}"
        -H "${height}"
        -r "${refresh}"
    )
}

gamescope_append_extra_args() {
    local -n args_ref="$1"
    local extra="${GAMESCOPE_EXTRA_ARGS:-}"
    local extra_args=()

    if [[ -z "${extra}" ]]; then
        return 0
    fi

    read -r -a extra_args <<< "${extra}"
    args_ref+=("${extra_args[@]}")
}

gamescope_env_flag_enabled() {
    local name="$1"
    local value="${!name:-off}"

    case "${value,,}" in
        1|true|yes|on)
            return 0
            ;;
        0|false|no|off)
            return 1
            ;;
        *)
            log_warn "${name}: unknown value '${value}', defaulting to off"
            return 1
            ;;
    esac
}
