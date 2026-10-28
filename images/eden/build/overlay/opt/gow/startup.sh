#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

# The AppImage is unpacked at build time, so the bundle's self-updater has no
# AppImage file to replace. Disable it explicitly instead of relying on the
# extracted-tree detection in upstream's AppRun hook.
export DISABLE_AUTO_UPDATES=1

# sharun (the AppImage runtime Eden uses) keeps the bundled Mesa Vulkan stack
# and hides system ICDs. On NVIDIA hosts that stack cannot drive the GPU: the
# base image copies the host driver's ICD to /usr/share/vulkan/icd.d and exports
# VK_DRIVER_FILES, so let the loader see it. AMD/Intel hosts keep the bundled
# drivers, which are self-contained and newer than the distro Mesa.
if [[ -f /usr/share/vulkan/icd.d/nvidia_icd.json ]]; then
    export SHARUN_ALLOW_SYS_VKICD="${SHARUN_ALLOW_SYS_VKICD:-1}"
fi

# Encryption keys are user-supplied. They are copied from a read-only mount
# rather than bind-mounted into the profile home: the base image chowns the
# whole home at startup, which fails on a read-only mount below it.
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
