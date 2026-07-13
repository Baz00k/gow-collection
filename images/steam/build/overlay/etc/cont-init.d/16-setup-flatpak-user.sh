#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

if [ "${PUID}" = "0" ]; then
    log_warn "PUID=0, skipping Flatpak authorization group setup"
    return 0 2>/dev/null || exit 0
fi

if ! getent group gow-flatpak >/dev/null 2>&1; then
    groupadd --system gow-flatpak
fi

usermod -aG gow-flatpak "${UNAME}"
