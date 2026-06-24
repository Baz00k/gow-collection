#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

export HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_DESKTOP=KDE
export XDG_SESSION_TYPE=wayland
export KDE_FULL_SESSION=true
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1

mkdir -p \
    "${HOME}/Desktop" \
    "${HOME}/.local/share/applications" \
    "${HOME}/.local/share/flatpak" \
    "${HOME}/.config"

flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || \
    log_warn "Could not configure user Flathub remote"

if command -v startplasma-wayland >/dev/null 2>&1; then
    log_info "Starting Plasma Wayland session"
    exec dbus-run-session -- startplasma-wayland
fi

log_error "startplasma-wayland not found"
exit 1
