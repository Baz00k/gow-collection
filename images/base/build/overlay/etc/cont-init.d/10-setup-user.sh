#!/bin/bash
set -euo pipefail

# shellcheck source=/dev/null
source /opt/gow/logging.sh

# XDG_RUNTIME_DIR and /tmp/.X11-unix are different runtime surfaces. Keep the
# XDG runtime dir private for Wayland, PulseAudio, and session IPC. Keep the X11
# socket dir sticky world-writable so X servers such as Xwayland can create X<N>
# sockets there while clients can connect. The X11 socket dir is shared
# infrastructure independent of the runtime user, so prepare it even for PUID=0.
log_info "Ensuring X11 socket directory exists at /tmp/.X11-unix"
install -d -m 1777 /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

if [ "${PUID}" = "0" ]; then
    log_warn "PUID=0, running as root (no runtime user creation)"
    # shellcheck disable=SC2317 # Script may be sourced by the init runner.
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

log_info "Creating /home/deck symlink -> ${UHOME}"
ln -sf "${UHOME}" /home/deck

log_info "Ensuring XDG_RUNTIME_DIR exists at ${XDG_RUNTIME_DIR}"
install -d -m 700 -o "${PUID}" -g "${PGID}" "${XDG_RUNTIME_DIR}"

log_info "Setting runtime ownership for ${UHOME} and ${XDG_RUNTIME_DIR}"
chown -R "${PUID}:${PGID}" "${UHOME}" "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"
