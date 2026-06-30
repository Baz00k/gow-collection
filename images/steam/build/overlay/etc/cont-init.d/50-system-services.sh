#!/bin/bash
set -euo pipefail

# System service bootstrap for Steam on Fedora (runs as ROOT before user switch)
# Starts: dbus-daemon, bluetoothd, NetworkManager, D-Bus watchdog, Decky Loader

# shellcheck source=/dev/null
source /opt/gow/logging.sh

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
    log_debug "DBus started"
    return 0
}

start_bluetooth() {
    local bluetoothd_path
    bluetoothd_path="$(command -v bluetoothd || true)"
    bluetoothd_path="${bluetoothd_path:-/usr/libexec/bluetooth/bluetoothd}"

    if [ ! -x "${bluetoothd_path}" ]; then
        gow_log "WARNING: bluetoothd not found, skipping"
        return 1
    fi
    "${bluetoothd_path}" --nodetach &
    log_debug "Bluez started"
    return 0
}

start_networkmanager() {
    if ! command -v NetworkManager &>/dev/null; then
        gow_log "WARNING: NetworkManager not found, skipping"
        return 1
    fi
    NetworkManager &
    log_debug "NetworkManager started"
    return 0
}

start_dbus_watchdog() {
    if [ ! -x /usr/local/bin/steamos-dbus-watchdog.sh ]; then
        gow_log "WARNING: steamos-dbus-watchdog.sh not found, skipping"
        return 1
    fi
    /usr/local/bin/steamos-dbus-watchdog.sh &
    log_debug "D-Bus Watchdog started"
    return 0
}

start_decky_loader() {
    if [ ! -f /opt/decky/PluginLoader ]; then
        gow_log "*** Decky Loader not found in /opt/decky, skipping ***"
        return 0
    fi

    UHOME="${UHOME:-${HOME:-/home/retro}}"

    local homebrew_dir
    local services_dir
    local plugins_dir
    local version_file

    homebrew_dir="${UHOME}/homebrew"
    services_dir="${homebrew_dir}/services"
    plugins_dir="${homebrew_dir}/plugins"
    version_file="${services_dir}/.loader.version"

    # Steam's bin_steam.sh creates ~/.steam/steam as a symlink to
    # ~/.local/share/Steam during bootstrap. If we mkdir it first the
    # symlink creation silently fails and Steam refuses to start with
    # "Couldn't set up Steam data". Use the real data path instead.
    STEAM_DATA="${UHOME}/.local/share/Steam"
    mkdir -p "${STEAM_DATA}"

    if ! touch "${STEAM_DATA}/.cef-enable-remote-debugging"; then
        gow_log "WARNING: Failed to create .cef-enable-remote-debugging"
        return 1
    fi

    mkdir -p "${services_dir}" "${plugins_dir}"

    if [ ! -f "${services_dir}/PluginLoader" ] || ! cmp -s /opt/decky/PluginLoader "${services_dir}/PluginLoader"; then
        if ! cp /opt/decky/PluginLoader "${services_dir}/PluginLoader"; then
            gow_log "WARNING: Failed to copy PluginLoader"
            return 1
        fi
        if ! chmod +x "${services_dir}/PluginLoader"; then
            gow_log "WARNING: Failed to make PluginLoader executable"
            return 1
        fi
    fi

    if [ -f /opt/decky/.loader.version ]; then
        cp /opt/decky/.loader.version "${version_file}" || true
    fi

    chown -R "${PUID:-1000}:${PGID:-1000}" "${homebrew_dir}" "${STEAM_DATA}" 2>/dev/null || true

    log_debug "Starting Decky Loader"
    (
        cd "${services_dir}"
        UNPRIVILEGED_PATH="${homebrew_dir}" \
            PRIVILEGED_PATH="${homebrew_dir}" \
            LOG_LEVEL="${DECKY_LOG_LEVEL:-INFO}" \
            "${services_dir}/PluginLoader"
    ) &

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
