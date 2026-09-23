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

# Poll the kernel socket tables instead of opening a TCP connection: a
# /dev/tcp probe would be accepted by wivrn-server as a headset handshake
# and log a spurious "Client connection failed: Socket shutdown" on boot.
wait_for_port() {
    local port="$1"
    local port_hex start now
    port_hex="$(printf '%04X' "${port}")"
    start="$(date +%s)"
    while true; do
        if command -v ss >/dev/null 2>&1; then
            if ss -ltn 2>/dev/null | grep -qE ":${port}([[:space:]]|$)"; then
                log_info "wivrn-server listening on port ${port}"
                return 0
            fi
        elif grep -qiE ":${port_hex}[[:space:]]+[0-9A-Fa-f:.]+[[:space:]]+0A" /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
            log_info "wivrn-server listening on port ${port}"
            return 0
        fi
        now="$(date +%s)"
        if (( now - start >= WIVRN_WAIT_TIMEOUT )); then
            log_warn "wivrn-server port ${port} did not open; continuing anyway"
            return 0
        fi
        sleep 1
    done
}

# --- WiVRn runtime config ---------------------------------------------------
/opt/gow/wivrn-config.sh

# WiVRn 26.9 chooses the first existing Steam root in this order:
# ~/.steam/debian-installation, then ~/.local/share/Steam. Fedora Steam may
# create the former as an empty directory while writing the VR manifest to
# the latter. Let WiVRn see the real manifest without modifying either Steam
# installation or replacing a manifest that already exists at the first root.
STEAM_VR_MANIFEST="${HOME}/.local/share/Steam/config/steamapps.vrmanifest"
DEBIAN_STEAM_ROOT="${HOME}/.steam/debian-installation"
if [[ -d "${DEBIAN_STEAM_ROOT}" && ! -e "${DEBIAN_STEAM_ROOT}/config/steamapps.vrmanifest" && ! -L "${DEBIAN_STEAM_ROOT}/config/steamapps.vrmanifest" && -f "${STEAM_VR_MANIFEST}" ]]; then
    mkdir -p "${DEBIAN_STEAM_ROOT}/config"
    # Relative target also resolves through Wolf's bind-mounted home in tests.
    ln -s "../../../.local/share/Steam/config/steamapps.vrmanifest" "${DEBIAN_STEAM_ROOT}/config/steamapps.vrmanifest"
    log_info "Linked Steam VR manifest for WiVRn app discovery"
fi

# --- Steam / Pressure Vessel integration ------------------------------------
# Steam sandboxes games with Pressure Vessel, which hides the host /usr
# (games see it as /run/host/usr) and does not pass the OpenXR runtime
# through unless asked. Upstream WiVRn prints the required per-game launch
# options at startup ("For Steam games, set command to ... %command%"),
# but in this container Steam only runs here, so apply them globally:
# every game inherits them and no per-game launch options are needed.
#
# This mirrors upstream WiVRn server/main.cpp steam_command():
#   /usr/... -> VR_OVERRIDE=/run/host/usr/... (host /usr is remapped)
#   $HOME/... -> usable as-is (home is shared into the sandbox)
#   anything else absolute -> passthrough via PRESSURE_VESSEL_FILESYSTEMS_RW
# An explicit VR_OVERRIDE from the environment is always respected.
# These exports must happen BEFORE wivrn-server starts so headset-initiated
# launches (which inherit the server environment) get them too.
if [[ -z "${PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES:-}" ]]; then
    export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
fi
log_info "PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=${PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES}"

if [[ -z "${VR_OVERRIDE:-}" ]]; then
    _compat="${WIVRN_OPENVR_COMPAT_PATH:-/usr/lib64/opencomposite/runtime}"
    _compat_lower="${_compat,,}"
    case "${_compat_lower}" in
        ""|"auto"|"off"|"none"|"null"|"disabled")
            log_info "OpenVR compat management disabled (WIVRN_OPENVR_COMPAT_PATH=${_compat}); leaving VR_OVERRIDE unset"
            ;;
        *)
            case "${_compat}" in
                /usr/*)
                    export VR_OVERRIDE="/run/host${_compat}"
                    log_info "VR_OVERRIDE=${VR_OVERRIDE} (translated for Pressure Vessel)"
                    ;;
                "${HOME}"/*)
                    export VR_OVERRIDE="${_compat}"
                    log_info "VR_OVERRIDE=${VR_OVERRIDE} (under HOME, shared into sandbox as-is)"
                    ;;
                /*)
                    export VR_OVERRIDE="${_compat}"
                    if [[ -z "${PRESSURE_VESSEL_FILESYSTEMS_RW:-}" ]]; then
                        export PRESSURE_VESSEL_FILESYSTEMS_RW="${_compat}"
                    else
                        export PRESSURE_VESSEL_FILESYSTEMS_RW="${PRESSURE_VESSEL_FILESYSTEMS_RW}:${_compat}"
                    fi
                    log_warn "OpenVR compat path ${_compat} is outside /usr and HOME; exported VR_OVERRIDE as-is and added to PRESSURE_VESSEL_FILESYSTEMS_RW"
                    ;;
                *)
                    log_warn "Ignoring unexpected WIVRN_OPENVR_COMPAT_PATH=${_compat}; leaving VR_OVERRIDE unset"
                    ;;
            esac
            # The compat path must contain bin/linux64/vrclient.so — that is
            # what WiVRn (active_runtime.cpp) and the OpenVR loader resolve
            # underneath it. A wrong level silently drops games to desktop
            # mode (no HMD image, no tracking), so fail the check loudly.
            # (Fedora nests it: /usr/lib64/opencomposite/runtime.)
            if [[ -n "${VR_OVERRIDE:-}" ]]; then
                if [[ ! -f "${_compat}/bin/linux64/vrclient.so" ]]; then
                    log_error "OpenVR compat library missing: ${_compat}/bin/linux64/vrclient.so not found; OpenVR games will fall back to desktop mode"
                else
                    log_info "OpenVR compat library ok: ${_compat}/bin/linux64/vrclient.so"
                fi
            fi
            ;;
    esac
    unset _compat _compat_lower
else
    export VR_OVERRIDE
    log_info "VR_OVERRIDE=${VR_OVERRIDE} (explicit override)"
fi

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
