#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
UNAME="retro"
UHOME="/home/${UNAME}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/.X11-unix}"
export PUID PGID UNAME UHOME XDG_RUNTIME_DIR

if ! [[ "${PUID}" =~ ^[0-9]+$ ]]; then
    log_error "PUID must be a numeric value, got: ${PUID}"
    exit 1
fi

if ! [[ "${PGID}" =~ ^[0-9]+$ ]]; then
    log_error "PGID must be a numeric value, got: ${PGID}"
    exit 1
fi

run_container_init() {
    if [ ! -d /etc/cont-init.d ]; then
        return 0
    fi

    for init_script in /etc/cont-init.d/*.sh; do
        if [ -f "${init_script}" ]; then
            log_info "Executing init script: ${init_script}"
            # shellcheck source=/dev/null
            source "${init_script}"
        fi
    done
}

if [ "$(id -u)" = "0" ]; then
    log_info "Configuring container for user '${UNAME}' with PUID=${PUID}, PGID=${PGID}"
    run_container_init
    /opt/gow/apply-performance-tuning.sh || true
fi

if [ $# -gt 0 ]; then
    log_info "Running custom command: $*"
    if [ "${PUID}" != "0" ] && [ "$(id -u)" = "0" ]; then
        exec gosu "${UNAME}" env HOME="${UHOME}" "$@"
    else
        exec "$@"
    fi
fi

if [ ! -f /opt/gow/startup.sh ]; then
    log_error "Startup script not found: /opt/gow/startup.sh"
    exit 1
fi

if [ "${PUID}" != "0" ] && [ "$(id -u)" = "0" ]; then
    log_info "Launching Steam session as user '${UNAME}'"
    exec gosu "${UNAME}" env HOME="${UHOME}" /opt/gow/startup.sh
else
    log_info "Launching Steam session as root"
    exec /opt/gow/startup.sh
fi
