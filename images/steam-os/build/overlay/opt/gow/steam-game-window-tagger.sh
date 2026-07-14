#!/bin/bash
set -euo pipefail

# shellcheck source=/dev/null
source /opt/gow/logging.sh

TAGGER_INTERVAL="${STEAM_WINDOW_TAGGER_INTERVAL:-1}"
MIN_WINDOW_WIDTH="${STEAM_WINDOW_TAGGER_MIN_WIDTH:-640}"
MIN_WINDOW_HEIGHT="${STEAM_WINDOW_TAGGER_MIN_HEIGHT:-360}"
XWININFO_BIN="${XWININFO_BIN:-/usr/bin/xwininfo}"
XPROP_BIN="${XPROP_BIN:-/usr/bin/xprop}"
PGREP_BIN="${PGREP_BIN:-/usr/bin/pgrep}"

active_steam_app_id() {
    local line app_id last_app_id=""

    while IFS= read -r line; do
        if [[ "${line}" =~ SteamLaunch[[:space:]]+AppId=([0-9]+) ]]; then
            app_id="${BASH_REMATCH[1]}"
            if [[ "${app_id}" != "0" ]]; then
                last_app_id="${app_id}"
            fi
        fi
    done < <("${PGREP_BIN}" -a -u "$(id -u)" -f 'SteamLaunch AppId=[0-9]+' 2>/dev/null || true)

    [[ -n "${last_app_id}" ]] || return 1
    printf '%s\n' "${last_app_id}"
}

tag_broken_windows() {
    local app_id="$1"
    local line window_id width height class existing

    while IFS= read -r line; do
        if [[ ! "${line}" =~ ^[[:space:]]+(0x[0-9a-fA-F]+)[[:space:]].*[[:space:]]([0-9]+)x([0-9]+)[+-] ]]; then
            continue
        fi

        window_id="${BASH_REMATCH[1]}"
        width="${BASH_REMATCH[2]}"
        height="${BASH_REMATCH[3]}"

        if (( width < MIN_WINDOW_WIDTH || height < MIN_WINDOW_HEIGHT )); then
            continue
        fi

        class="$("${XPROP_BIN}" -id "${window_id}" WM_CLASS 2>/dev/null || true)"
        if [[ "${class}" != 'WM_CLASS(STRING) = "steam_app_0", "steam_app_0"' ]]; then
            continue
        fi

        existing="$("${XPROP_BIN}" -id "${window_id}" STEAM_GAME 2>/dev/null || true)"
        if [[ "${existing}" == "STEAM_GAME(CARDINAL) = ${app_id}" ]]; then
            continue
        fi

        if "${XPROP_BIN}" -id "${window_id}" -f STEAM_GAME 32c -set STEAM_GAME "${app_id}" 2>/dev/null; then
            log_info "Tagged Steam game window ${window_id} with AppId=${app_id}"
        fi
    done < <("${XWININFO_BIN}" -root -tree 2>/dev/null || true)
}

if [[ -z "${DISPLAY:-}" ]]; then
    log_warn "Steam game window tagger disabled: DISPLAY is not set"
    exit 0
fi

if [[ ! -x "${XWININFO_BIN}" ]] || [[ ! -x "${XPROP_BIN}" ]] || [[ ! -x "${PGREP_BIN}" ]]; then
    log_warn "Steam game window tagger disabled: required X11 tools are missing"
    exit 0
fi

log_info "Steam game window tagger started"

while true; do
    if app_id="$(active_steam_app_id)"; then
        tag_broken_windows "${app_id}"
    fi

    sleep "${TAGGER_INTERVAL}"
done
