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
UNAME="retro"
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

# Export runtime user for use by system services (e.g., dbus watchdog needs to know which user runs Steam)
export UNAME
export UHOME

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

        log_info "Ensuring XDG_RUNTIME_DIR exists at ${XDG_RUNTIME_DIR}"
        mkdir -p "${XDG_RUNTIME_DIR}"
        log_info "Ensuring XDG_RUNTIME_DIR is writable by ${UNAME}:${UNAME}"
        chown -R "${PUID}:${PGID}" "${XDG_RUNTIME_DIR}"
        chmod 0700 "${XDG_RUNTIME_DIR}"

        # Create Steam runtime directories
        log_info "Creating Steam runtime directories"
        mkdir -p "${UHOME}/.steam"
        mkdir -p "${UHOME}/.local/share/Steam"

        # Migrate legacy layout: if ~/.steam/steam is a real directory (created
        # by older images), move its contents into ~/.local/share/Steam/ and
        # replace it with the symlink that bin_steam.sh expects.
        if [ -d "${UHOME}/.steam/steam" ] && [ ! -L "${UHOME}/.steam/steam" ]; then
            log_warn "Migrating legacy ~/.steam/steam directory to ~/.local/share/Steam"
            cp -a "${UHOME}/.steam/steam/." "${UHOME}/.local/share/Steam/" 2>/dev/null || true
            rm -rf "${UHOME}/.steam/steam"
            ln -sfn "${UHOME}/.local/share/Steam" "${UHOME}/.steam/steam"
        fi

        chown -R "${PUID}:${PGID}" "${UHOME}/.steam"
        chown -R "${PUID}:${PGID}" "${UHOME}/.local"

        # =====================================================================
        # Device group handling (matches upstream GoW ensure-groups pattern)
        # Adds user to groups owning GPU/input devices so gamescope can access
        # DRM primary nodes (/dev/dri/card*) and NVIDIA devices.
        # =====================================================================
        log_info "Configuring device group access"
        declare -A _dev_groups
        for _dev_glob in /dev/dri/* /dev/nvidia*; do
            # shellcheck disable=SC2086
            for _dev in $_dev_glob; do
                if [ -e "${_dev}" ]; then
                    _gname=$(stat -c "%G" "${_dev}")
                    _gid=$(stat -c "%g" "${_dev}")
                    if [ "${_gname}" = "UNKNOWN" ]; then
                        _gname="gow-gid-${_gid}"
                        if ! getent group "${_gname}" > /dev/null 2>&1; then
                            groupadd -g "${_gid}" "${_gname}"
                        fi
                    fi
                    _dev_groups[${_gname}]=1
                    # Ensure group has read/write access
                    if [ "$(stat -c "%a" "${_dev}" | cut -c2)" -lt 6 ]; then
                        chmod g+rw "${_dev}"
                    fi
                fi
            done
        done
        if [ ${#_dev_groups[@]} -gt 0 ]; then
            _groups_csv=$(IFS=,; echo "${!_dev_groups[*]}")
            log_info "Adding user '${UNAME}' to device groups: ${_groups_csv}"
            usermod -aG "${_groups_csv}" "${UNAME}"
        fi
        unset _dev_groups _dev_glob _dev _gname _gid _groups_csv
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
        exec gosu "${UNAME}" "$@"
    else
        exec "$@"
    fi
fi

# =============================================================================
# Launch startup script
# =============================================================================
if [ "${PUID}" != "0" ] && [ "$(id -u)" = "0" ]; then
    log_info "Launching startup script as user '${UNAME}'"
    if [ ! -f /opt/gow/startup.sh ]; then
        log_error "Startup script not found: /opt/gow/startup.sh"
        exit 1
    fi
    chmod +x /opt/gow/startup.sh
    exec gosu "${UNAME}" /opt/gow/startup.sh
else
    log_info "Launching startup script as root"
    if [ ! -f /opt/gow/startup.sh ]; then
        log_error "Startup script not found: /opt/gow/startup.sh"
        exit 1
    fi
    chmod +x /opt/gow/startup.sh
    exec /opt/gow/startup.sh
fi
