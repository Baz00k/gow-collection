#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

# The image strips gamescope's file capability, because with cap_sys_nice it
# cannot exec when the runner does not grant SYS_NICE. When the runner does
# grant it, add the capability so gamescope raises its CPU priority and asks
# for realtime GPU queues. It drops LD_PRELOAD only for itself, which is fine
# here: Steam runs inside gamescope and sets the overlay preload for its games.
if ! capsh --has-b=cap_sys_nice 2>/dev/null; then
    log_info "[gamescope] SYS_NICE not granted; compositor runs at regular priority"
elif ! setcap cap_sys_nice+ep /usr/bin/gamescope 2>/dev/null; then
    log_warn "[gamescope] could not set cap_sys_nice; compositor runs at regular priority"
fi
