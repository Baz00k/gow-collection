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

update_activation_environment
/usr/bin/ibus-daemon -d -r --panel=disable --emoji-extension=disable || true

# An empty WAYLAND_DISPLAY still counts as set for games: pressure-vessel
# passes it in as wayland-0 without a socket, and Proton builds that prefer
# Wayland then pick winewayland and never show a window. Like before gamescope
# ran Steam, games must see it unset and use X11.
unset WAYLAND_DISPLAY
exec /usr/bin/steam "$@"
