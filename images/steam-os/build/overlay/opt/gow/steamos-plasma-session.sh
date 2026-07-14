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

        # KWin manages its own Xwayland and generates a per-session X authority
        # file, but it does not export DISPLAY/XAUTHORITY into the session bus.
        # Discover both from the kwin_wayland command line so X11 clients such as
        # Steam and Flatpak apps can connect and authenticate against Xwayland.
        wait_for_kwin_x11_display() {
            local kwin_pid index arg next_is_display next_is_xauthority
            local display display_number display_socket xauthority
            local -a kwin_args

            for _ in {1..50}; do
                for kwin_pid in $(pgrep -x kwin_wayland); do
                    # Translate the NUL-delimited cmdline into array elements.
                    mapfile -t kwin_args < <(tr "\0" "\n" < "/proc/${kwin_pid}/cmdline")

                    next_is_display=""
                    next_is_xauthority=""
                    display=""
                    xauthority=""

                    for index in "${!kwin_args[@]}"; do
                        arg="${kwin_args[${index}]}"
                        if [[ -n "${next_is_display}" ]]; then
                            display="${arg}"
                            next_is_display=""
                            continue
                        fi
                        if [[ -n "${next_is_xauthority}" ]]; then
                            xauthority="${arg}"
                            next_is_xauthority=""
                            continue
                        fi
                        case "${arg}" in
                            --xwayland-display) next_is_display=1 ;;
                            --xwayland-xauthority) next_is_xauthority=1 ;;
                        esac
                    done

                    [[ "${display}" =~ ^:[0-9]+$ ]] || continue
                    display_number="${display#:}"
                    display_socket="/tmp/.X11-unix/X${display_number}"
                    [[ -S "${display_socket}" ]] || continue
                    if [[ -n "${xauthority}" && ! -s "${xauthority}" ]]; then
                        continue
                    fi

                    export DISPLAY="${display}"
                    if [[ -n "${xauthority}" ]]; then
                        export XAUTHORITY="${xauthority}"
                    fi
                    return 0
                done

                sleep 0.1
            done

            log_warn "KWin Xwayland display did not become available"
            return 1
        }

        update_session_environment() {
            if command -v dbus-update-activation-environment >/dev/null 2>&1; then
                dbus-update-activation-environment \
                    WAYLAND_DISPLAY \
                    DISPLAY \
                    XAUTHORITY \
                    XDG_RUNTIME_DIR \
                    DBUS_SESSION_BUS_ADDRESS \
                    HOME \
                    PATH \
                    XDG_CURRENT_DESKTOP \
                    XDG_SESSION_DESKTOP \
                    XDG_SESSION_TYPE \
                    KDE_FULL_SESSION \
                    KDE_SESSION_VERSION \
                    XDG_DATA_DIRS || log_warn "dbus-update-activation-environment failed"
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
        wait_for_kwin_x11_display || true
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
