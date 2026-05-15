#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} [nvidia] $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} [nvidia] $*"; }

NVIDIA_DIR="/usr/nvidia"

finish_nvidia_init() {
    return 0 2>/dev/null || exit 0
}

if [ -d "${NVIDIA_DIR}/lib" ] || [ -d "${NVIDIA_DIR}/lib32" ]; then
    log_info "NVIDIA driver volume detected at ${NVIDIA_DIR}"
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
elif [ -e /usr/lib64/libnvidia-allocator.so.1 ]; then
    log_info "NVIDIA toolkit libraries detected"

    if [ ! -e /usr/lib64/gbm/nvidia-drm_gbm.so ]; then
        log_info "Creating NVIDIA GBM backend symlink"
        mkdir -p /usr/lib64/gbm
        ln -sv ../libnvidia-allocator.so.1 /usr/lib64/gbm/nvidia-drm_gbm.so
    fi

    if [ ! -f /usr/share/glvnd/egl_vendor.d/10_nvidia.json ]; then
        log_info "Creating NVIDIA EGL vendor config"
        mkdir -p /usr/share/glvnd/egl_vendor.d/
        cat > /usr/share/glvnd/egl_vendor.d/10_nvidia.json <<'EOF'
{
  "file_format_version": "1.0.0",
  "ICD": {
    "library_path": "libEGL_nvidia.so.0"
  }
}
EOF
    fi

    if [ ! -f /usr/share/vulkan/icd.d/nvidia_icd.json ]; then
        log_info "Creating NVIDIA Vulkan ICD config"
        mkdir -p /usr/share/vulkan/icd.d/
        cat > /usr/share/vulkan/icd.d/nvidia_icd.json <<'EOF'
{
  "file_format_version": "1.0.0",
  "ICD": {
    "library_path": "libGLX_nvidia.so.0",
    "api_version": "1.3.242"
  }
}
EOF
        export VK_DRIVER_FILES="/usr/share/vulkan/icd.d/nvidia_icd.json"
    fi

    if [ ! -f /usr/share/egl/egl_external_platform.d/15_nvidia_gbm.json ]; then
        log_info "Creating NVIDIA GBM external platform config"
        mkdir -p /usr/share/egl/egl_external_platform.d/
        cat > /usr/share/egl/egl_external_platform.d/15_nvidia_gbm.json <<'EOF'
{
  "file_format_version": "1.0.0",
  "ICD": {
    "library_path": "libnvidia-egl-gbm.so.1"
  }
}
EOF
    fi

    if [ ! -f /usr/share/egl/egl_external_platform.d/10_nvidia_wayland.json ]; then
        log_info "Creating NVIDIA Wayland external platform config"
        mkdir -p /usr/share/egl/egl_external_platform.d/
        cat > /usr/share/egl/egl_external_platform.d/10_nvidia_wayland.json <<'EOF'
{
  "file_format_version": "1.0.0",
  "ICD": {
    "library_path": "libnvidia-egl-wayland.so.1"
  }
}
EOF
    fi

    HOST_NVRTC=$(ldconfig -p 2>/dev/null \
        | awk '/libnvrtc\.so[^.0-9]/{print $NF}' \
        | grep -v '/usr/local/nvidia/lib' \
        | head -1 || true)
    if [ -n "${HOST_NVRTC}" ]; then
        log_info "Preferring host nvrtc over baked-in: ${HOST_NVRTC}"
        mkdir -p /usr/local/nvidia/lib
        ln -sf "${HOST_NVRTC}" /usr/local/nvidia/lib/libnvrtc.so
    fi
else
    log_warn "No NVIDIA driver volume or toolkit libraries detected, skipping"
    finish_nvidia_init
fi

log_info "Running ldconfig for NVIDIA libraries"
ldconfig
log_info "NVIDIA driver integration complete"
