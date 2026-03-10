#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} [nvidia] $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} [nvidia] $*"; }

NVIDIA_DIR="/usr/nvidia"

if [ ! -d "${NVIDIA_DIR}/lib" ] && [ ! -d "${NVIDIA_DIR}/lib32" ]; then
    log_warn "No NVIDIA driver volume at ${NVIDIA_DIR}, skipping"
    exit 0
fi

log_info "Setting LD_LIBRARY_PATH for NVIDIA libraries"
export LD_LIBRARY_PATH="${NVIDIA_DIR}/lib:${NVIDIA_DIR}/lib32${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Copy Vulkan ICD, EGL, GLX vendor, and GBM backend configs from the mounted
# driver volume into the standard search paths. Matches upstream GoW base-app 30-nvidia.sh.
if [ -d "${NVIDIA_DIR}/share/vulkan/icd.d" ]; then
    log_info "Copying Vulkan ICD configs"
    mkdir -p /usr/share/vulkan/icd.d/
    cp "${NVIDIA_DIR}"/share/vulkan/icd.d/* /usr/share/vulkan/icd.d/
    log_info "Setting VK_DRIVER_FILES to NVIDIA ICD only"
    export VK_DRIVER_FILES="/usr/share/vulkan/icd.d/nvidia_icd.json"
fi

if [ -d "${NVIDIA_DIR}/share/egl/egl_external_platform.d" ]; then
    log_info "Copying EGL external platform configs"
    mkdir -p /usr/share/egl/egl_external_platform.d/
    cp "${NVIDIA_DIR}"/share/egl/egl_external_platform.d/* /usr/share/egl/egl_external_platform.d/
fi

if [ -d "${NVIDIA_DIR}/share/glvnd/egl_vendor.d" ]; then
    log_info "Copying EGL vendor configs"
    mkdir -p /usr/share/glvnd/egl_vendor.d/
    cp "${NVIDIA_DIR}"/share/glvnd/egl_vendor.d/* /usr/share/glvnd/egl_vendor.d/
fi

if [ -d "${NVIDIA_DIR}/lib/gbm" ]; then
    log_info "Copying GBM backend"
    mkdir -p /usr/lib64/gbm/
    cp "${NVIDIA_DIR}"/lib/gbm/* /usr/lib64/gbm/
fi

log_info "Running ldconfig for NVIDIA libraries"
ldconfig
log_info "NVIDIA driver integration complete"
