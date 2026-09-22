#!/bin/bash
set -euo pipefail

# WiVRn + Steam session (runs as the runtime user under dbus-run-session).
# Starts PipeWire audio, wivrn-server, then Steam inside gamescope.
# All services are invoked by bare command name so tests can PATH-stub them.

# shellcheck source=/dev/null
source /opt/gow/logging.sh
# shellcheck source=/dev/null
source /opt/gow/gamescope-lib.sh

export HOME="${HOME:-$(getent passwd "$(whoami)" | cut -d: -f6)}"
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR

WIVRN_PORT="${WIVRN_PORT:-9757}"
WIVRN_WAIT_TIMEOUT="${WIVRN_WAIT_TIMEOUT:-15}"
STEAM_STARTUP_FLAGS="${STEAM_STARTUP_FLAGS:-}"

SERVICE_PIDS=()

track_pid() {
    SERVICE_PIDS+=("$1")
}

cleanup_services() {
    local pid
    for pid in "${SERVICE_PIDS[@]}"; do
        kill "${pid}" 2>/dev/null || true
    done
    wait 2>/dev/null || true
}
trap cleanup_services EXIT

wait_for_socket() {
    local socket_path="$1"
    local label="$2"
    local start now
    start="$(date +%s)"
    while [[ ! -S "${socket_path}" ]]; do
        now="$(date +%s)"
        if (( now - start >= WIVRN_WAIT_TIMEOUT )); then
            log_warn "${label} socket did not appear at ${socket_path}; continuing anyway"
            return 0
        fi
        sleep 1
    done
    log_info "${label} ready at ${socket_path}"
}

wait_for_port() {
    local port="$1"
    local start now
    start="$(date +%s)"
    while ! (echo > "/dev/tcp/127.0.0.1/${port}") 2>/dev/null; do
        now="$(date +%s)"
        if (( now - start >= WIVRN_WAIT_TIMEOUT )); then
            log_warn "wivrn-server port ${port} did not open; continuing anyway"
            return 0
        fi
        sleep 1
    done
    log_info "wivrn-server listening on port ${port}"
}

# --- WiVRn runtime config ---------------------------------------------------
/opt/gow/wivrn-config.sh

# --- Audio: PipeWire + WirePlumber (replaces Wolf's PulseAudio) -------------
log_info "Starting PipeWire audio"
pipewire &
track_pid "$!"
pipewire-pulse &
track_pid "$!"
wireplumber &
track_pid "$!"

wait_for_socket "${XDG_RUNTIME_DIR}/pipewire-0" "PipeWire"
wait_for_socket "${XDG_RUNTIME_DIR}/pulse/native" "pipewire-pulse"

unset PULSE_SERVER
unset PULSE_SINK
unset PULSE_SOURCE
export PULSE_SERVER="unix:${XDG_RUNTIME_DIR}/pulse/native"
log_info "PULSE_SERVER=${PULSE_SERVER}"

# --- WiVRn server ------------------------------------------------------------
log_info "Starting wivrn-server (port ${WIVRN_PORT})"
wivrn-server &
track_pid "$!"
wait_for_port "${WIVRN_PORT}"

# Steam (Pressure Vessel) only imports host OpenXR runtimes when told to.
export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1

# --- Steam inside gamescope ---------------------------------------------------
read -r -a STEAM_ARGS <<< "${STEAM_STARTUP_FLAGS}"

GAMESCOPE_ARGS=()
gamescope_require_runtime_dir
gamescope_append_base_args GAMESCOPE_ARGS
gamescope_append_extra_args GAMESCOPE_ARGS
GAMESCOPE_ARGS+=(-e --steam --mangoapp)

if [[ "${#STEAM_ARGS[@]}" -gt 0 ]]; then
    log_info "Launching Steam with flags: ${STEAM_STARTUP_FLAGS}"
else
    log_info "Launching Steam"
fi
exec gamescope "${GAMESCOPE_ARGS[@]}" -- steam "${STEAM_ARGS[@]}"
