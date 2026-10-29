#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

# The Dockerfile strips gamescope's cap_sys_nice file capability so it can exec
# without SYS_NICE. Put it back when the runner grants SYS_NICE, so the
# compositor gets realtime scheduling.
if ! capsh --has-b=cap_sys_nice 2>/dev/null; then
    log_info "[gamescope] SYS_NICE not granted; compositor runs at regular priority"
elif ! setcap cap_sys_nice+ep /usr/bin/gamescope 2>/dev/null; then
    log_warn "[gamescope] could not restore cap_sys_nice; compositor runs at regular priority"
fi
