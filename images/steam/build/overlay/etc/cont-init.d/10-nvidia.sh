#!/bin/bash
set -euo pipefail

# =============================================================================
# NVIDIA Driver Integration for Wolf runtime model
# =============================================================================
# Wolf mounts host NVIDIA drivers at /usr/nvidia via a Docker volume.
# Static config is baked into the image (ld.so.conf.d, ENV vars for Vulkan/EGL).
# This script only needs to run ldconfig so the linker picks up the mounted libs.
# =============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} [nvidia] $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} [nvidia] $*"; }

NVIDIA_DIR="/usr/nvidia"

if [ ! -d "${NVIDIA_DIR}/lib" ] && [ ! -d "${NVIDIA_DIR}/lib32" ]; then
    log_warn "No NVIDIA driver volume at ${NVIDIA_DIR}, skipping ldconfig"
    exit 0
fi

log_info "Running ldconfig for NVIDIA libraries"
ldconfig
log_info "NVIDIA driver integration complete"
