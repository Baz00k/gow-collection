#!/bin/bash
set -euo pipefail

# shellcheck source=/dev/null
source /opt/gow/logging.sh

export HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_DESKTOP=KDE
export XDG_SESSION_TYPE=wayland
export KDE_FULL_SESSION=true
export KDE_SESSION_VERSION=6
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export XDG_DATA_DIRS="${HOME}/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

mkdir -p \
    "${HOME}/Desktop" \
    "${HOME}/.local/share/applications" \
    "${HOME}/.local/share/flatpak" \
    "${HOME}/.config"

install -m 755 \
    /usr/share/applications/return-to-steam.desktop \
    "${HOME}/Desktop/return-to-steam.desktop"

flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || \
    log_warn "Could not configure user Flathub remote"

if command -v startplasma-wayland >/dev/null 2>&1; then
    log_info "Starting Plasma Wayland session"
    # Plasma classic boot does not reach phase-0 autostart in this container, so keep the shell on the same session bus.
    # shellcheck disable=SC2016 # Inner bash expands session variables after dbus-run-session starts.
    exec dbus-run-session -- bash -c '
        set -euo pipefail

        source /opt/gow/logging.sh

        startplasma-wayland &
        plasma_pid=$!
        shell_pid=""

        cleanup() {
            if [[ -n "${shell_pid}" ]]; then
                kill "${shell_pid}" 2>/dev/null || true
            fi
            kill "${plasma_pid}" 2>/dev/null || true
            wait "${shell_pid}" 2>/dev/null || true
            wait "${plasma_pid}" 2>/dev/null || true
        }
        trap cleanup EXIT INT TERM

        sleep 2

        if ! pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then
            log_info "Starting Plasma shell"
            plasmashell --replace &
            shell_pid=$!
        fi

        wait "${plasma_pid}"
    '
fi

log_error "startplasma-wayland not found"
exit 1
