#!/bin/bash
set -euo pipefail

# Gamescope's primary child. DISPLAY, GAMESCOPE_WAYLAND_DISPLAY and the empty
# WAYLAND_DISPLAY (which keeps clients off Wolf's compositor) come from gamescope.

# shellcheck source=/dev/null
source /opt/gow/logging.sh

# Gamescope's WSI layer is what paces in-game vsync on the nested backend.
# Gamescope sets this for its children too; keep it explicit. 0 opts out.
export ENABLE_GAMESCOPE_WSI="${ENABLE_GAMESCOPE_WSI:-1}"

update_activation_environment() {
    if ! command -v dbus-update-activation-environment >/dev/null 2>&1; then
        log_warn "dbus-update-activation-environment not found; D-Bus activated services keep the outer environment"
        return 0
    fi

    dbus-update-activation-environment \
        DISPLAY \
        WAYLAND_DISPLAY \
        GAMESCOPE_WAYLAND_DISPLAY \
        XDG_RUNTIME_DIR || log_warn "dbus-update-activation-environment failed"
}

# With two Xwaylands, Steam caps its UI at 1920x1080 and, with no mode list
# from nested gamescope, uses that as the native game resolution. Steam's
# Developer toggle "Enable Native Resolution on External Displays" skips the
# cap. Seed it on once; a user who turns it off keeps their choice.
seed_steam_native_resolution() {
    local config="${HOME}/.local/share/Steam/config/config.vdf"
    local key="EnableSteamNativeExternalResolution"
    local tmp

    if [ ! -f "${config}" ]; then
        mkdir -p "$(dirname "${config}")"
        printf '"InstallConfigStore"\n{\n\t"Gamescope"\n\t{\n\t\t"%s"\t\t"1"\n\t}\n}\n' "${key}" > "${config}"
        return 0
    fi
    grep -q "\"${key}\"" "${config}" && return 0

    tmp="$(mktemp "${config}.XXXXXX")"
    # Add the key to the top-level "Gamescope" block, or add that block
    # before the root's closing brace.
    if awk -v key="${key}" '
        { line[NR] = $0; t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t); trim[NR] = t }
        END {
            depth = 0; gs = 0; root_end = 0
            for (i = 1; i <= NR; i++) {
                if (trim[i] == "{") depth++
                else if (trim[i] == "}") { depth--; if (depth == 0) root_end = i }
                else if (depth == 1 && trim[i] == "\"Gamescope\"" && trim[i + 1] == "{") gs = i + 1
            }
            if (!root_end) exit 1
            for (i = 1; i <= NR; i++) {
                if (i == root_end && !gs) printf "\t\"Gamescope\"\n\t{\n\t\t\"%s\"\t\t\"1\"\n\t}\n", key
                print line[i]
                if (i == gs) printf "\t\t\"%s\"\t\t\"1\"\n", key
            }
        }' "${config}" > "${tmp}"; then
        mv -f "${tmp}" "${config}"
    else
        rm -f "${tmp}"
        log_warn "Could not seed ${key} in ${config}; Steam may cap games at 1920x1080"
    fi
}

update_activation_environment
seed_steam_native_resolution
/usr/bin/ibus-daemon -d -r --panel=disable --emoji-extension=disable || true

# An empty WAYLAND_DISPLAY still counts as set for games: pressure-vessel
# passes it in as wayland-0 without a socket, and Proton builds that prefer
# Wayland then pick winewayland and never show a window. Like before gamescope
# ran Steam, games must see it unset and use X11.
unset WAYLAND_DISPLAY
exec /usr/bin/steam "$@"
