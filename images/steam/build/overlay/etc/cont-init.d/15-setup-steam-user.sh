#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

fail_init() {
    return 1 2>/dev/null || exit 1
}

if [ "${PUID}" = "0" ]; then
    log_warn "PUID=0, skipping Steam runtime user setup"
    return 0 2>/dev/null || exit 0
fi

log_info "Creating Steam runtime directories"
mkdir -p "${UHOME}/.steam" "${UHOME}/.local/share/Steam"

if [ -d "${UHOME}/.steam/steam" ] && [ ! -L "${UHOME}/.steam/steam" ]; then
    log_error "Legacy ~/.steam/steam directory detected; automatic migration is disabled"
    log_error "Move ~/.steam/steam/* into ~/.local/share/Steam/ manually, then remove ~/.steam/steam so the symlink can be recreated"
    fail_init
fi

log_info "Setting Steam runtime ownership for ${UHOME}"
chown -R "${PUID}:${PGID}" "${UHOME}/.steam" "${UHOME}/.local"

if [ -f /usr/bin/gamescope ]; then
    log_info "Setting gamescope ownership to ${UNAME}:${UNAME}"
    chown "${UNAME}:${UNAME}" /usr/bin/gamescope 2>/dev/null || true
fi
