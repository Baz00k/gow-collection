# syntax=docker/dockerfile:1.4

# -----------------------------------------------------------------------------
# Shared Fedora base for the gow-collection images.
# -----------------------------------------------------------------------------
# Provides the common Games on Whales runtime contract that every app image in
# this repo builds on:
#   - runtime user creation + gosu privilege-drop handoff (entrypoint.sh)
#   - /etc/cont-init.d/* init-script runner (user, devices, NVIDIA)
#   - shared logging + performance-tuning helpers
#   - non-setuid bubblewrap for Flatpak sandboxing
# -----------------------------------------------------------------------------
ARG BASE_IMAGE
ARG BASE_IMAGE_DIGEST

# hadolint ignore=DL3006
FROM ${BASE_IMAGE}@${BASE_IMAGE_DIGEST}

# -----------------------------------------------------------------------------
# Shared runtime packages
# -----------------------------------------------------------------------------
# hadolint ignore=DL3041
RUN <<'_INSTALL_PACKAGES' bash
set -eux

packages=(
    # Core shell utils
    bash
    coreutils
    curl
    findutils
    procps-ng
    shadow-utils
    util-linux
    neovim

    # Graphics and compositor stack shared by downstream app images
    gamescope
    xorg-x11-server-Xwayland
    fontconfig
    glibc-langpack-en

    # Mesa/Vulkan runtime drivers and loaders
    mesa-dri-drivers
    mesa-vulkan-drivers
    mesa-va-drivers
    mesa-libEGL
    mesa-libGL
    mesa-libgbm
    vulkan-loader

    # Hardware discovery
    pciutils

    # Flatpak sandbox helper
    bubblewrap

    # FUSE for AppImage
    fuse
    fuse3
)

dnf install -y --setopt=install_weak_deps=False "${packages[@]}"

dnf clean all
rm -rf /var/cache/dnf
_INSTALL_PACKAGES

# -----------------------------------------------------------------------------
# gosu — privilege dropping tool
# -----------------------------------------------------------------------------
ARG GOSU_AMD64_URL
ARG GOSU_AMD64_SHA256

RUN curl -fsSL -o /usr/bin/gosu "${GOSU_AMD64_URL}" && \
    echo "${GOSU_AMD64_SHA256}  /usr/bin/gosu" | sha256sum -c - && \
    chmod +x /usr/bin/gosu

# -----------------------------------------------------------------------------
# NVIDIA linker search paths
# -----------------------------------------------------------------------------
# Wolf mounts NVIDIA drivers at /usr/nvidia — pre-configure linker search paths.
# Vulkan ICD and EGL configs are copied at runtime by 30-nvidia.sh.
RUN printf '%s\n' '/usr/nvidia/lib' '/usr/nvidia/lib32' > /etc/ld.so.conf.d/nvidia.conf

# Build-time /home/deck -> /home/retro convenience symlink. 10-setup-user.sh
# re-points it at runtime if UHOME differs from the default.
RUN ln -sf /home/retro /home/deck

# -----------------------------------------------------------------------------
# Shared overlay (entrypoint, logging, cont-init scripts)
# -----------------------------------------------------------------------------
COPY --chmod=755 overlay /

# This is a base-image contract for every downstream app: Flatpak must run bwrap
# in unprivileged/non-setuid mode so flatpak-spawn --share-pids and --expose-pids
# work. Proton/UMU launchers use that path from Flatpak apps such as Heroic. If a
# runtime blocks unprivileged user namespaces, fix the Wolf/Docker runner profile;
RUN chmod 0755 /usr/bin/bwrap

# -----------------------------------------------------------------------------
# Environment and Labels
# -----------------------------------------------------------------------------
ENV LANG=C.UTF-8

ARG IMAGE_SOURCE="https://github.com/Baz00k/gow-collection"

LABEL org.opencontainers.image.title="Base image for gow-collection (Fedora)"
LABEL org.opencontainers.image.description="Shared Fedora base with the Games on Whales runtime contract (user setup, gosu handoff, cont-init, bubblewrap)"
LABEL org.opencontainers.image.authors="Baz00k"
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
LABEL org.opencontainers.image.licenses="GPL-3.0-only"

# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------
ENTRYPOINT ["/opt/gow/entrypoint.sh"]
