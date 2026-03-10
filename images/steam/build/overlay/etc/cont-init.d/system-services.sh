#!/bin/bash
set -euo pipefail

# System service bootstrap for Steam on Fedora (runs as ROOT before user switch)
# Starts: dbus-daemon, bluetoothd, NetworkManager, D-Bus watchdog, Decky Loader

gow_log() { echo "$(date +"[%Y-%m-%d %H:%M:%S]") $*"; }

start_dbus() {
    if ! mkdir -p /run/dbus; then
        gow_log "WARNING: Failed to create /run/dbus directory"
        return 1
    fi
    if ! dbus-daemon --system --fork --nosyslog; then
        gow_log "WARNING: Failed to start D-Bus daemon"
        return 1
    fi
    gow_log "*** DBus started ***"
    return 0
}

start_bluetooth() {
    if ! command -v bluetoothd &>/dev/null; then
        gow_log "WARNING: bluetoothd not found, skipping"
        return 1
    fi
    bluetoothd --nodetach &
    gow_log "*** Bluez started ***"
    return 0
}

start_networkmanager() {
    if ! command -v NetworkManager &>/dev/null; then
        gow_log "WARNING: NetworkManager not found, skipping"
        return 1
    fi
    NetworkManager &
    gow_log "*** NetworkManager started ***"
    return 0
}

start_dbus_watchdog() {
    if [[ "${GAMESCOPE_STEAM_MODE:-off}" != "on" ]]; then
        gow_log "D-Bus watchdog skipped (GAMESCOPE_STEAM_MODE!=on)"
        return 0
    fi
    if [ ! -x /usr/local/bin/steamos-dbus-watchdog.sh ]; then
        gow_log "WARNING: steamos-dbus-watchdog.sh not found, skipping"
        return 1
    fi
    /usr/local/bin/steamos-dbus-watchdog.sh &
    gow_log "*** D-Bus Watchdog started ***"
    return 0
}

start_decky_loader() {
    if [ ! -f /opt/decky/PluginLoader ]; then
        gow_log "*** Decky Loader not found in /opt/decky, skipping ***"
        return 0
    fi

    UHOME="${UHOME:-${HOME:-/root}}"

    # Steam's bin_steam.sh creates ~/.steam/steam as a symlink to
    # ~/.local/share/Steam during bootstrap.  If we mkdir it first the
    # symlink creation silently fails and Steam refuses to start with
    # "Couldn't set up Steam data".  Use the real data path instead.
    STEAM_DATA="${UHOME}/.local/share/Steam"
    mkdir -p "${STEAM_DATA}"

    if ! touch "${STEAM_DATA}/.cef-enable-remote-debugging"; then
        gow_log "WARNING: Failed to create .cef-enable-remote-debugging"
        return 1
    fi

    mkdir -p "${UHOME}/homebrew/services/"

    if [ ! -f "${UHOME}/homebrew/services/PluginLoader" ]; then
        if ! cp /opt/decky/PluginLoader "${UHOME}/homebrew/services/PluginLoader"; then
            gow_log "WARNING: Failed to copy PluginLoader"
            return 1
        fi
        if ! chmod +x "${UHOME}/homebrew/services/PluginLoader"; then
            gow_log "WARNING: Failed to make PluginLoader executable"
            return 1
        fi
    fi

    gow_log "*** Starting Decky Loader ***"
    "${UHOME}/homebrew/services/PluginLoader" &

    return 0
}

gow_log "=== Starting system services ==="

start_dbus || true
start_bluetooth || true
start_networkmanager || true
start_dbus_watchdog || true
start_decky_loader || true

disown

gow_log "=== System services bootstrap complete ==="
