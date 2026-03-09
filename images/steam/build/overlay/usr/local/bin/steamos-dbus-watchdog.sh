#!/bin/bash
set -euo pipefail

# D-Bus watchdog — intercepts Steam power menu actions (PowerOff, Reboot, Suspend)
# and gracefully shuts down Steam instead of trying to power off the container.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }

shutdown_steam() {
    log_info "[steamos-dbus-watchdog] Shutting down Steam..."
    /usr/bin/steam -shutdown
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
