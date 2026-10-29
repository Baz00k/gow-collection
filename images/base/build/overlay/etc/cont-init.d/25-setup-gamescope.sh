#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

# gamescope asks for realtime scheduling through the cap_sys_nice file capability
# that Fedora packages onto /usr/bin/gamescope. The Dockerfile strips it so the
# compositor still starts when the runner profile does not grant CAP_SYS_NICE:
# the kernel refuses to exec a file capability that the bounding set lacks.
#
# Restore it here when the profile does grant the capability, which is the
# documented starting configuration for every app image.
if [ ! -x /usr/bin/gamescope ]; then
    return 0 2>/dev/null || exit 0
fi

if ! command -v setcap > /dev/null 2>&1 || ! command -v capsh > /dev/null 2>&1; then
    log_warn "[gamescope] libcap tools missing; compositor runs at regular priority"
    return 0 2>/dev/null || exit 0
fi

bounding_set="$(capsh --print 2>/dev/null | sed -n 's/^Bounding set =//p' || true)"
if [[ -z "${bounding_set}" ]] || [[ ",${bounding_set}," != *",cap_sys_nice,"* ]]; then
    log_info "[gamescope] CAP_SYS_NICE not granted by the runner; compositor runs at regular priority"
    return 0 2>/dev/null || exit 0
fi

if setcap cap_sys_nice+ep /usr/bin/gamescope 2>/dev/null; then
    log_info "[gamescope] CAP_SYS_NICE granted; gamescope file capability restored"
else
    log_warn "[gamescope] CAP_SYS_NICE granted but /usr/bin/gamescope could not be marked; compositor runs at regular priority"
fi
