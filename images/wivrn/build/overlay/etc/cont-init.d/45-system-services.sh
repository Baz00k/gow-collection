#!/bin/bash
set -euo pipefail

# WiVRn system services (runs as ROOT via cont-init before the user switch).
# Starts the system D-Bus daemon and Avahi mDNS publishing, then prepares the
# WiVRn/OpenXR runtime directories for the runtime user.

# shellcheck source=/dev/null
source /opt/gow/logging.sh

UHOME="${UHOME:-${HOME:-/home/retro}}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

start_dbus() {
    if ! mkdir -p /run/dbus; then
        log_warn "Failed to create /run/dbus directory"
        return 1
    fi
    if ! dbus-daemon --system --fork --nosyslog; then
        log_warn "Failed to start system D-Bus daemon"
        return 1
    fi
    log_debug "System D-Bus started"
    return 0
}

start_avahi() {
    local avahi_bin avahi_pid
    avahi_bin="$(command -v avahi-daemon || true)"
    if [[ -z "${avahi_bin}" ]]; then
        log_warn "avahi-daemon not found, skipping mDNS publishing"
        return 1
    fi
    # Launch in the background: avahi-daemon may stay in the foreground
    # depending on build flags, and cont-init must never block on it.
    "${avahi_bin}" --no-chroot &
    avahi_pid="$!"
    disown 2>/dev/null || true
    sleep 2
    if kill -0 "${avahi_pid}" 2>/dev/null || pgrep -x avahi-daemon >/dev/null 2>&1; then
        log_debug "Avahi started"
        return 0
    fi
    log_warn "avahi-daemon did not stay running"
    return 1
}

setup_wivrn_dirs() {
    local openxr_dir="${UHOME}/.config/openxr/1"
    local openvr_dir="${UHOME}/.config/openvr"
    local wivrn_dir="${UHOME}/.local/share/wivrn"

    if ! mkdir -p "${openxr_dir}" "${openvr_dir}" "${wivrn_dir}"; then
        log_warn "Failed to create WiVRn runtime directories"
        return 1
    fi

    if [[ "${PUID}" == "0" ]]; then
        log_debug "PUID=0, skipping WiVRn directory ownership setup"
        return 0
    fi

    if ! chown "${PUID}:${PGID}" \
        "${UHOME}/.config" \
        "${UHOME}/.config/openxr" \
        "${openxr_dir}" \
        "${openvr_dir}" \
        "${UHOME}/.local" \
        "${UHOME}/.local/share" \
        "${wivrn_dir}"; then
        log_warn "Failed to set ownership on WiVRn runtime directories"
        return 1
    fi
    log_debug "WiVRn runtime directories ready"
    return 0
}

log_info "Starting WiVRn system services"

start_dbus || true
start_avahi || true
setup_wivrn_dirs || true

# Detach any remaining background jobs. There may be none (avahi-daemon
# daemonizes on its own), so never fail here: this file is sourced, and a
# non-zero status would abort container init under `set -e`.
disown 2>/dev/null || true

log_info "WiVRn system services bootstrap complete"
