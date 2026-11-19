# syntax=docker/dockerfile:1.4
ARG BASE_APP_IMAGE

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

ARG DECKY_LOADER_VERSION
ARG DECKY_LOADER_URL
ARG DECKY_LOADER_SHA256

# -----------------------------------------------------------------------------
# Package Installation
# -----------------------------------------------------------------------------
# hadolint ignore=DL3041
RUN <<'_INSTALL_PACKAGES' bash
set -eux

packages=(
    # Gaming overlays/performance helpers (MangoHud from Terra)
    gamemode
    terra-mangohud.x86_64
    terra-mangohud.i686

    # Desktop services Steam and KDE expect to be available at runtime
    bluez
    dbus-daemon
    ibus
    NetworkManager
    # Docker owns eth0, so NM only reports "online" (which Discover requires)
    # after an HTTP connectivity check succeeds.
    NetworkManager-config-connectivity-fedora

    # General desktop integration helpers used by Steam, Flatpak, and launchers
    file
    lsb-release
    xdg-user-dirs
    xdg-utils
    xz
    zenity

    # KDE Plasma desktop session used when Steam exits to desktop mode
    dolphin
    kdialog
    konsole
    kwin
    kwin-wayland
    plasma-desktop
    plasma-discover
    plasma-discover-flatpak
    plasma-workspace
    plasma-workspace-wayland
    firefox

    # Portal and Flatpak support for desktop apps and Flathub integration
    flatpak
    xdg-desktop-portal
    xdg-desktop-portal-kde

    # Fonts
    dejavu-fonts-all
    google-noto-fonts-common
    google-noto-sans-cjk-vf-fonts

    # Scripting utilities used by Steam-specific init and helper scripts
    jq
    python3
)

dnf install -y --setopt=install_weak_deps=False "${packages[@]}"

# Steam client from Terra, never RPM Fusion's: fails if Terra drops it.
dnf install -y --setopt=install_weak_deps=False --from-repo=terra steam

# Firmware updates can't work in a container; the fwupd backend only makes
# Discover show "Update Issue" errors.
rm -f /usr/lib64/qt6/plugins/discover/fwupd-backend.so

dnf clean all
rm -rf /var/cache/dnf
_INSTALL_PACKAGES

# -----------------------------------------------------------------------------
# Decky Loader
# -----------------------------------------------------------------------------
RUN mkdir -p /opt/decky && \
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --retry-max-time 60 \
        -o /opt/decky/PluginLoader "${DECKY_LOADER_URL}" && \
    echo "${DECKY_LOADER_SHA256}  /opt/decky/PluginLoader" | sha256sum -c - && \
    chmod +x /opt/decky/PluginLoader && \
    echo "v${DECKY_LOADER_VERSION}" > /opt/decky/.loader.version

# -----------------------------------------------------------------------------
# System Configuration
# -----------------------------------------------------------------------------
RUN touch /etc/NetworkManager/conf.d/10-globally-managed-devices.conf

RUN flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    && flatpak remote-modify --enable flathub \
    && { flatpak --system update --appstream --noninteractive || true; }

RUN fc-cache -f -v

# -----------------------------------------------------------------------------
# Overlay (SteamOS session init, startup, and compatibility stubs)
# -----------------------------------------------------------------------------
COPY --chmod=755 overlay /

RUN mkdir -p /usr/games && \
    ln -sf /usr/bin/steam /usr/games/steam && \
    update-desktop-database /usr/share/applications

ARG IMAGE_SOURCE="https://github.com/Baz00k/gow-collection"

LABEL org.opencontainers.image.title="SteamOS for Games on Whales"
LABEL org.opencontainers.image.description="SteamOS-style gaming environment with gamescope and KDE Plasma for Wolf"
LABEL org.opencontainers.image.authors="Baz00k"
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
LABEL org.opencontainers.image.licenses="GPL-3.0-only"

# ENTRYPOINT is inherited from the base image (/opt/gow/entrypoint.sh).
