#!/bin/bash
set -euo pipefail

# =============================================================================
# Entrypoint for Steam container (Fedora-based)
# Handles PUID/PGID user mapping, init scripts, and privilege dropping
# =============================================================================

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

# =============================================================================
# User/Group Configuration
# =============================================================================

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
UNAME="steam"
UHOME="/home/${UNAME}"

# Validate PUID/PGID are numeric
if ! [[ "${PUID}" =~ ^[0-9]+$ ]]; then
    log_error "PUID must be a numeric value, got: ${PUID}"
    exit 1
fi

if ! [[ "${PGID}" =~ ^[0-9]+$ ]]; then
    log_error "PGID must be a numeric value, got: ${PGID}"
    exit 1
fi

log_info "Configuring user '${UNAME}' with PUID=${PUID}, PGID=${PGID}"

# =============================================================================
# Root-only initialization
# =============================================================================
if [ "$(id -u)" = "0" ]; then
    # Create /run/dbus directory for D-Bus system bus
    log_info "Creating /run/dbus directory"
    mkdir -p /run/dbus

    # Create user if PUID is not 0 (not running as root)
    if [ "${PUID}" != "0" ]; then
        log_info "Creating user '${UNAME}' with UID=${PUID}, GID=${PGID}"
        
        # Create group if it doesn't exist
        if ! getent group "${UNAME}" > /dev/null 2>&1; then
            groupadd -g "${PGID}" "${UNAME}"
            log_info "Created group '${UNAME}' with GID ${PGID}"
        else
            # Group exists, update GID if different
            existing_gid=$(getent group "${UNAME}" | cut -d: -f3)
            if [ "${existing_gid}" != "${PGID}" ]; then
                log_warn "Group '${UNAME}' exists with GID ${existing_gid}, updating to ${PGID}"
                groupmod -g "${PGID}" "${UNAME}"
            fi
        fi

        # Create user if it doesn't exist
        if ! id -u "${UNAME}" > /dev/null 2>&1; then
            useradd -u "${PUID}" -g "${PGID}" -d "${UHOME}" -m -s /bin/bash "${UNAME}"
            log_info "Created user '${UNAME}' with UID ${PUID}"
        else
            # User exists, update UID if different
            existing_uid=$(id -u "${UNAME}")
            if [ "${existing_uid}" != "${PUID}" ]; then
                log_warn "User '${UNAME}' exists with UID ${existing_uid}, updating to ${PUID}"
                usermod -u "${PUID}" "${UNAME}"
            fi
            # Ensure home directory exists
            if [ ! -d "${UHOME}" ]; then
                mkdir -p "${UHOME}"
            fi
        fi

        # Ensure home directory ownership
        log_info "Setting ownership of ${UHOME} to ${PUID}:${PGID}"
        chown -R "${PUID}:${PGID}" "${UHOME}"

        # Create /home/deck symlink for Decky Loader compatibility
        log_info "Creating /home/deck symlink -> ${UHOME}"
        ln -sf "${UHOME}" /home/deck

        # Set gamescope permissions for non-root user
        if [ -f /usr/bin/gamescope ]; then
            log_info "Setting gamescope ownership to ${UNAME}:${UNAME}"
            chown "${UNAME}:${UNAME}" /usr/bin/gamescope 2>/dev/null || true
        fi

        # Set XDG_RUNTIME_DIR only if not already provided by Wolf
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/.X11-unix}"
        export XDG_RUNTIME_DIR

        log_info "Creating XDG_RUNTIME_DIR at ${XDG_RUNTIME_DIR}"
        mkdir -p "${XDG_RUNTIME_DIR}"
        chown "${UNAME}:${UNAME}" "${XDG_RUNTIME_DIR}"
        chmod 1777 "${XDG_RUNTIME_DIR}"

        # Create Steam runtime directories
        log_info "Creating Steam runtime directories"
        mkdir -p "${UHOME}/.steam"
        mkdir -p "${UHOME}/.local/share/Steam"
        chown -R "${PUID}:${PGID}" "${UHOME}/.steam"
        chown -R "${PUID}:${PGID}" "${UHOME}/.local"
    else
        log_warn "PUID=0, running as root (no user creation)"
    fi

    # Execute all container init scripts from /etc/cont-init.d/
    if [ -d /etc/cont-init.d ]; then
        for init_script in /etc/cont-init.d/*.sh; do
            if [ -f "${init_script}" ]; then
                log_info "Executing init script: ${init_script}"
                # shellcheck source=/dev/null
                source "${init_script}"
            fi
        done
    fi
fi

# =============================================================================
# Handle command passthrough
# =============================================================================
# If a command was passed, run that instead of the usual startup script
if [ $# -gt 0 ]; then
    log_info "Running custom command: $*"
    if [ "${PUID}" != "0" ] && [ "$(id -u)" = "0" ]; then
        exec runuser --preserve-environment -u "${UNAME}" -- "$@"
    else
        exec "$@"
    fi
fi

# =============================================================================
# Launch startup script
# =============================================================================
if [ "${PUID}" != "0" ] && [ "$(id -u)" = "0" ]; then
    log_info "Launching startup script as user '${UNAME}'"
    if [ ! -f /opt/gow/startup-app.sh ]; then
        log_error "Startup script not found: /opt/gow/startup-app.sh"
        exit 1
    fi
    chmod +x /opt/gow/startup-app.sh
    exec runuser --preserve-environment -u "${UNAME}" -- /opt/gow/startup-app.sh
else
    log_info "Launching startup script as root"
    if [ ! -f /opt/gow/startup-app.sh ]; then
        log_error "Startup script not found: /opt/gow/startup-app.sh"
        exit 1
    fi
    chmod +x /opt/gow/startup-app.sh
    exec /opt/gow/startup-app.sh
fi
