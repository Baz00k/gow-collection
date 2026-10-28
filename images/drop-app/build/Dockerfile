# syntax=docker/dockerfile:1.4
ARG BASE_APP_IMAGE

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

ARG DROP_APP_VERSION
ARG DROP_APP_TAG
ARG DROP_APP_RPM_X86_64_URL
ARG DROP_APP_RPM_X86_64_SHA256
ARG UMU_LAUNCHER_RPM_FLAVOUR
ARG UMU_LAUNCHER_RPM_X86_64_URL
ARG UMU_LAUNCHER_RPM_X86_64_SHA256

# hadolint ignore=DL3041
RUN <<'_INSTALL_DROP_APP' bash
set -eux

packages=(
    # General desktop integration helpers used by the Drop desktop client
    xdg-utils

    # GTK tray indicator and embedded WebKit runtime required by the Drop desktop RPM
    libayatana-appindicator-gtk3
    webkit2gtk4.1

    # Browser fallback and URL opener support for external auth/help flows
    firefox
)

dnf install -y --setopt=install_weak_deps=False "${packages[@]}"

curl -fsSL -o /tmp/drop-desktop-client.rpm "${DROP_APP_RPM_X86_64_URL}"
curl -fsSL -o /tmp/umu-launcher.rpm "${UMU_LAUNCHER_RPM_X86_64_URL}"
echo "${DROP_APP_RPM_X86_64_SHA256}  /tmp/drop-desktop-client.rpm" | sha256sum -c -
echo "${UMU_LAUNCHER_RPM_X86_64_SHA256}  /tmp/umu-launcher.rpm" | sha256sum -c -

# Pinned upstream Drop desktop client RPM
dnf install -y /tmp/drop-desktop-client.rpm

# UMU launcher, used by the client to start Windows games through Proton
dnf install -y /tmp/umu-launcher.rpm

# Directory the client scans for Proton builds
install -d /usr/share/steam/compatibilitytools.d

rm -f /tmp/drop-desktop-client.rpm /tmp/umu-launcher.rpm
dnf clean all
rm -rf /var/cache/dnf
_INSTALL_DROP_APP

COPY --chmod=755 overlay /

ENV BROWSER=firefox
ENV WEBKIT_DISABLE_DMABUF_RENDERER=1

ARG IMAGE_SOURCE="https://github.com/Baz00k/gow-collection"

LABEL org.opencontainers.image.title="Drop App for Games on Whales"
LABEL org.opencontainers.image.description="Drop desktop client for cloud gaming via Games on Whales/Wolf"
LABEL org.opencontainers.image.authors="Baz00k"
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
LABEL org.opencontainers.image.licenses="GPL-3.0-only"
