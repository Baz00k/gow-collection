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
unset KWIN_WAYLAND_NO_XWAYLAND

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

        declare -A existing_wayland_displays=()

        wait_for_kwin_wayland_display() {
            local display_socket display_name

            for _ in {1..50}; do
                for display_socket in "${XDG_RUNTIME_DIR}"/wayland-*; do
                    [[ -S "${display_socket}" ]] || continue
                    display_name="${display_socket##*/}"
                    [[ -z "${existing_wayland_displays[${display_name}]:-}" ]] || continue
                    export WAYLAND_DISPLAY="${display_name}"
                    return 0
                done

                sleep 0.1
            done

            log_warn "KWin Wayland display did not become available"
        }

        wait_for_xwayland_display() {
            local display_socket display_path

            for _ in {1..300}; do
                for display_socket in /tmp/.X11-unix/X*; do
                    [[ -S "${display_socket}" ]] || continue
                    display_path="${display_socket##*/X}"
                    export DISPLAY=":${display_path}"
                    log_info "Detected KWin Xwayland display: DISPLAY=${DISPLAY}"
                    return 0
                done

                sleep 0.1
            done

            log_warn "KWin Xwayland display did not become available; X11 apps including Steam will fail"
            pgrep -a kwin_wayland || true
            pgrep -a Xwayland || true
            ls -la /tmp/.X11-unix || true
            command -v Xwayland >/dev/null 2>&1 && Xwayland -version || true
        }

        update_session_environment() {
            if command -v dbus-update-activation-environment >/dev/null 2>&1; then
                dbus-update-activation-environment \
                    DISPLAY \
                    WAYLAND_DISPLAY \
                    XDG_RUNTIME_DIR \
                    DBUS_SESSION_BUS_ADDRESS \
                    HOME \
                    PATH \
                    XDG_CURRENT_DESKTOP \
                    XDG_SESSION_DESKTOP \
                    XDG_SESSION_TYPE \
                    KDE_FULL_SESSION \
                    KDE_SESSION_VERSION \
                    XDG_DATA_DIRS \
                    QT_QPA_PLATFORM \
                    MOZ_ENABLE_WAYLAND || log_warn "dbus-update-activation-environment failed"
            fi
        }

        for display_socket in "${XDG_RUNTIME_DIR}"/wayland-*; do
            [[ -S "${display_socket}" ]] || continue
            existing_wayland_displays["${display_socket##*/}"]=1
        done

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

        wait_for_kwin_wayland_display
        wait_for_xwayland_display
        update_session_environment

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
