#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

log_info "Steam startup.sh"

export HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"
mkdir -p "${HOME}/.steam/ubuntu12_32/steam-runtime"

exec /opt/gow/steamos-session-supervisor.sh
