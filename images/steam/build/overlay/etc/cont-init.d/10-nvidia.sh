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

# Copy Vulkan ICD, EGL, and GLX vendor configs from the mounted driver volume
# into the standard search paths. Matches upstream GoW base-app 30-nvidia.sh.
if [ -d "${NVIDIA_DIR}/share/vulkan/icd.d" ]; then
    log_info "Copying Vulkan ICD configs"
    mkdir -p /usr/share/vulkan/icd.d/
    cp "${NVIDIA_DIR}"/share/vulkan/icd.d/* /usr/share/vulkan/icd.d/
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

log_info "Running ldconfig for NVIDIA libraries"
ldconfig
log_info "NVIDIA driver integration complete"
