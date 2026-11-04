#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

log_info "WiVRn startup.sh"

export HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"

# Workaround for steam-for-linux#6492; ~/.steam/ubuntu12_32 is the pre-2019 layout.
mkdir -p "${HOME}/.local/share/Steam/ubuntu12_32/steam-runtime"

exec dbus-run-session -- /opt/gow/wivrn-session.sh "$@"
