#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

log_info "WiVRn startup.sh"

export HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"
mkdir -p "${HOME}/.steam/ubuntu12_32/steam-runtime"

exec dbus-run-session -- /opt/gow/wivrn-session.sh "$@"
