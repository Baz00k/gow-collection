# syntax=docker/dockerfile:1.4
ARG BASE_APP_IMAGE

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

ARG RPMFUSION_FREE_URL
ARG RPMFUSION_FREE_SHA256
ARG RPMFUSION_NONFREE_URL
ARG RPMFUSION_NONFREE_SHA256
ARG DECKY_LOADER_VERSION
ARG DECKY_LOADER_URL
ARG DECKY_LOADER_SHA256

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
RUN dnf install -y \
    steam \
    mangohud \
    gamemode \
    dbus-daemon \
    NetworkManager \
    bluez \
    ibus \
    xz \
    zenity \
    file \
    xdg-user-dirs \
    xdg-utils \
    lsb-release \
    mesa-demos \
    vulkan-tools \
    plasma-workspace \
    plasma-workspace-wayland \
    plasma-desktop \
    plasma-discover \
    plasma-discover-flatpak \
    kwin \
    kwin-wayland \
    dolphin \
    konsole \
    kdialog \
    xdg-desktop-portal \
    xdg-desktop-portal-kde \
    flatpak \
    firefox \
    dejavu-fonts-all \
    google-noto-fonts-common \
    python3 \
    jq \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# -----------------------------------------------------------------------------
# Decky Loader
# -----------------------------------------------------------------------------
RUN mkdir -p /opt/decky && \
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --retry-max-time 60 \
        -o /opt/decky/PluginLoader "${DECKY_LOADER_URL}" && \
    echo "${DECKY_LOADER_SHA256}  /opt/decky/PluginLoader" | sha256sum -c - && \
    chmod +x /opt/decky/PluginLoader

# -----------------------------------------------------------------------------
# System Configuration
# -----------------------------------------------------------------------------
RUN touch /etc/NetworkManager/conf.d/10-globally-managed-devices.conf

RUN fc-cache -f -v

# -----------------------------------------------------------------------------
# Overlay (Steam-specific cont-init scripts, startup, SteamOS stubs)
# -----------------------------------------------------------------------------
COPY --chmod=755 overlay /

RUN mkdir -p /usr/games && \
    ln -sf /usr/bin/steam /usr/games/steam && \
    update-desktop-database /usr/share/applications

# -----------------------------------------------------------------------------
# Environment and Labels
# -----------------------------------------------------------------------------
ENV XDG_RUNTIME_DIR=/tmp/.X11-unix

ARG IMAGE_SOURCE="https://github.com/Baz00k/gow-collection"

LABEL org.opencontainers.image.title="Steam for Games on Whales (Fedora)"
LABEL org.opencontainers.image.description="Fedora-based Steam with gamescope for Wolf cloud gaming"
LABEL org.opencontainers.image.authors="Baz00k"
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
LABEL org.opencontainers.image.licenses="GPL-3.0-only"

# ENTRYPOINT is inherited from the base image (/opt/gow/entrypoint.sh).
