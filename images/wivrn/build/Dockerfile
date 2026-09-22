# syntax=docker/dockerfile:1.4
ARG BASE_APP_IMAGE

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

ARG RPMFUSION_FREE_URL
ARG RPMFUSION_FREE_SHA256
ARG RPMFUSION_NONFREE_URL
ARG RPMFUSION_NONFREE_SHA256

# -----------------------------------------------------------------------------
# RPM Fusion Setup
# -----------------------------------------------------------------------------
# Steam is in RPM Fusion nonfree repository. Must enable both free and nonfree.
# hadolint ignore=DL3041
RUN curl -fsSL -o /tmp/rpmfusion-free-release.rpm "${RPMFUSION_FREE_URL}" && \
    curl -fsSL -o /tmp/rpmfusion-nonfree-release.rpm "${RPMFUSION_NONFREE_URL}" && \
    echo "${RPMFUSION_FREE_SHA256}  /tmp/rpmfusion-free-release.rpm" | sha256sum -c - && \
    echo "${RPMFUSION_NONFREE_SHA256}  /tmp/rpmfusion-nonfree-release.rpm" | sha256sum -c - && \
    dnf install -y \
        /tmp/rpmfusion-free-release.rpm \
        /tmp/rpmfusion-nonfree-release.rpm && \
    dnf config-manager setopt fedora-cisco-openh264.enabled=1 && \
    rm -f /tmp/rpmfusion-free-release.rpm /tmp/rpmfusion-nonfree-release.rpm

# -----------------------------------------------------------------------------
# Package Installation
# -----------------------------------------------------------------------------
# hadolint ignore=DL3041
RUN <<'_INSTALL_PACKAGES' bash
set -eux

packages=(
    # Native WiVRn VR streaming server and OpenXR runtime
    # (pulls opencomposite for SteamVR/OpenVR compatibility)
    wivrn

    # Steam client and gaming overlays/performance helpers
    steam
    gamescope
    gamemode
    mangohud

    # PipeWire audio stack: this container replaces Wolf's PulseAudio with
    # PipeWire + WirePlumber so WiVRn can route VR audio to the headset
    pipewire
    pipewire-pulseaudio
    pipewire-utils
    wireplumber

    # mDNS discovery (headset finds the server) and D-Bus runtime
    avahi
    avahi-tools
    dbus-daemon
    dbus-tools

    # General desktop integration helpers used by Steam and launchers
    file
    lsb-release
    xwininfo
    xdg-user-dirs
    xdg-utils
    xz
    zenity
    desktop-file-utils

    # Vulkan diagnostics
    vulkan-tools

    # Fonts
    dejavu-fonts-all
    google-noto-fonts-common

    # Scripting utilities used by init and helper scripts
    jq
    python3
)

dnf install -y --setopt=install_weak_deps=False "${packages[@]}"

dnf clean all
rm -rf /var/cache/dnf
_INSTALL_PACKAGES

RUN fc-cache -f -v

# -----------------------------------------------------------------------------
# Overlay (WiVRn session init, startup, and config defaults)
# -----------------------------------------------------------------------------
COPY --chmod=755 overlay /

RUN mkdir -p /usr/games && \
    ln -sf /usr/bin/steam /usr/games/steam && \
    update-desktop-database /usr/share/applications

ARG IMAGE_SOURCE="https://github.com/Baz00k/gow-collection"

LABEL org.opencontainers.image.title="WiVRn + Steam for Games on Whales"
LABEL org.opencontainers.image.description="Native WiVRn VR streaming server with Steam in gamescope for Wolf"
LABEL org.opencontainers.image.authors="Baz00k"
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
LABEL org.opencontainers.image.licenses="GPL-3.0-only"

# ENTRYPOINT is inherited from the base image (/opt/gow/entrypoint.sh).
