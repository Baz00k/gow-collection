# syntax=docker/dockerfile:1.4
ARG BASE_APP_IMAGE

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

ARG DROP_APP_VERSION
ARG DROP_APP_RPM_X86_64_URL
ARG DROP_APP_RPM_X86_64_SHA256

# hadolint ignore=DL3041
RUN <<_INSTALL_DROP_APP
set -eux
dnf install -y \
    firefox \
    libayatana-appindicator-gtk3 \
    webkit2gtk4.1 \
    xdg-utils
curl -fsSL -o /tmp/drop-desktop-client.rpm "${DROP_APP_RPM_X86_64_URL}"
echo "${DROP_APP_RPM_X86_64_SHA256}  /tmp/drop-desktop-client.rpm" | sha256sum -c -
dnf install -y /tmp/drop-desktop-client.rpm
rm -f /tmp/drop-desktop-client.rpm
dnf clean all
rm -rf /var/cache/dnf
_INSTALL_DROP_APP

COPY --chmod=755 overlay /

RUN mkdir -p /tmp/.X11-unix
ENV XDG_RUNTIME_DIR=/tmp/.X11-unix
ENV BROWSER=firefox

# TODO: Once drop-app releases Proton/UMU support (currently on develop branch),
# install umu-run and a Proton build for Windows game compatibility.
# See: https://github.com/Drop-OSS/drop-app/blob/develop/src-tauri/process/src/compat.rs

ARG IMAGE_SOURCE="https://github.com/Baz00k/gow-collection"

LABEL org.opencontainers.image.title="Drop App for Games on Whales"
LABEL org.opencontainers.image.description="Drop desktop client for cloud gaming via Games on Whales/Wolf"
LABEL org.opencontainers.image.authors="Baz00k"
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
LABEL org.opencontainers.image.licenses="GPL-3.0-only"
