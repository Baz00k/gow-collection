#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

fail_init() {
    return 1 2>/dev/null || exit 1
}

if [ "${PUID}" = "0" ]; then
    log_warn "PUID=0, running as root (no runtime user creation)"
    return 0 2>/dev/null || exit 0
fi

log_info "Creating runtime user '${UNAME}' with UID=${PUID}, GID=${PGID}"

if ! getent group "${UNAME}" > /dev/null 2>&1; then
    groupadd -g "${PGID}" "${UNAME}"
    log_info "Created group '${UNAME}' with GID ${PGID}"
else
    existing_gid=$(getent group "${UNAME}" | cut -d: -f3)
    if [ "${existing_gid}" != "${PGID}" ]; then
        log_warn "Group '${UNAME}' exists with GID ${existing_gid}, updating to ${PGID}"
        groupmod -g "${PGID}" "${UNAME}"
    fi
fi

if ! id -u "${UNAME}" > /dev/null 2>&1; then
    useradd -u "${PUID}" -g "${PGID}" -d "${UHOME}" -m -s /bin/bash "${UNAME}"
    log_info "Created user '${UNAME}' with UID ${PUID}"
else
    existing_uid=$(id -u "${UNAME}")
    if [ "${existing_uid}" != "${PUID}" ]; then
        log_warn "User '${UNAME}' exists with UID ${existing_uid}, updating to ${PUID}"
        usermod -u "${PUID}" "${UNAME}"
    fi
    mkdir -p "${UHOME}"
fi

log_info "Creating Steam runtime directories"
mkdir -p "${UHOME}/.steam" "${UHOME}/.local/share/Steam"

if [ -d "${UHOME}/.steam/steam" ] && [ ! -L "${UHOME}/.steam/steam" ]; then
    log_error "Legacy ~/.steam/steam directory detected; automatic migration is disabled"
    log_error "Move ~/.steam/steam/* into ~/.local/share/Steam/ manually, then remove ~/.steam/steam so the symlink can be recreated"
    fail_init
fi

log_info "Creating /home/deck symlink -> ${UHOME}"
ln -sf "${UHOME}" /home/deck

log_info "Ensuring XDG_RUNTIME_DIR exists at ${XDG_RUNTIME_DIR}"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"

log_info "Setting runtime ownership for ${UHOME} and ${XDG_RUNTIME_DIR}"
chown -R "${PUID}:${PGID}" "${UHOME}" "${XDG_RUNTIME_DIR}"

if [ -f /usr/bin/gamescope ]; then
    log_info "Setting gamescope ownership to ${UNAME}:${UNAME}"
    chown "${UNAME}:${UNAME}" /usr/bin/gamescope 2>/dev/null || true
fi
