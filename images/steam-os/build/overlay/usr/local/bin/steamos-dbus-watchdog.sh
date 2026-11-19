#!/bin/bash
set -euo pipefail

# D-Bus watchdog — intercepts Steam power menu actions (PowerOff, Reboot, Suspend)
# and gracefully shuts down Steam instead of trying to power off the container.

# shellcheck source=/dev/null
source /opt/gow/logging.sh

shutdown_steam() {
    log_info "[steamos-dbus-watchdog] Shutting down Steam..."
    # Steam cannot run as root - use gosu to run as the runtime user
    local runtime_user="${UNAME:-retro}"
    gosu "${runtime_user}" /usr/bin/steam -shutdown
    exit 0
}

log_info "[steamos-dbus-watchdog] Starting D-Bus watcher for Steam shutdown..."
dbus-monitor --system "interface='org.freedesktop.login1.Manager'" | \
while read -r line; do
    if echo "$line" | grep -q "member=PowerOff"; then
        log_info "[steamos-dbus-watchdog] Detected 'PowerOff' D-Bus call!"
        shutdown_steam
    fi

    if echo "$line" | grep -q "member=Reboot"; then
        log_info "[steamos-dbus-watchdog] Detected 'Reboot' D-Bus call!"
        shutdown_steam
    fi

    if echo "$line" | grep -q "member=Suspend"; then
        log_info "[steamos-dbus-watchdog] Detected 'Suspend' D-Bus call!"
        shutdown_steam
    fi
done
