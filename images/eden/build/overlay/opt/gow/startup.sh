#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

# Image updates are applied by rebuilding, so runtime self-updates are off.
export DISABLE_AUTO_UPDATES=1

# sharun defaults to its bundled Mesa Vulkan stack. NVIDIA hosts need the host
# driver's ICD, which the base image publishes at /usr/share/vulkan/icd.d/.
if [[ -f /usr/share/vulkan/icd.d/nvidia_icd.json ]]; then
    export SHARUN_ALLOW_SYS_VKICD="${SHARUN_ALLOW_SYS_VKICD:-1}"
fi

# Keys come from a read-only mount and are copied into the profile: the base
# image chowns the home at startup, which fails on a read-only mount below it.
EDEN_KEYS_DIR="${EDEN_KEYS_DIR:-/keys}"
EDEN_HOME="${HOME:-/home/retro}"
if [[ -d "${EDEN_KEYS_DIR}" ]]; then
    keys_dir="${EDEN_HOME}/.local/share/eden/keys"
    mkdir -p "${keys_dir}"
    for key_file in "${EDEN_KEYS_DIR}"/*.keys; do
        [[ -e "${key_file}" ]] || continue
        target="${keys_dir}/$(basename "${key_file}")"
        [[ -f "${target}" ]] && continue
        cp "${key_file}" "${target}"
        log_info "Installed $(basename "${key_file}") from ${EDEN_KEYS_DIR}"
    done
fi

log_info "Starting Eden"
exec /opt/gow/launch-gamescope.sh /opt/eden/AppRun "$@"
