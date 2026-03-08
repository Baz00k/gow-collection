# syntax=docker/dockerfile:1.4
ARG BASE_APP_IMAGE

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG DROP_APP_VERSION
ARG DROP_APP_SHA256

# hadolint ignore=DL3008,DL3015
RUN <<_INSTALL_DROP_APP
set -e
# Remove the Ubuntu snap stub for Firefox (doesn't work in Docker)
apt-get update
apt-get remove -y firefox 2>/dev/null || true
# Add Mozilla's official APT repository for real Firefox .deb
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o /etc/apt/keyrings/mozilla.asc
echo "deb [signed-by=/etc/apt/keyrings/mozilla.asc] https://packages.mozilla.org/apt mozilla main" > /etc/apt/sources.list.d/mozilla.list
# Pin Mozilla repo so its Firefox always wins over the Ubuntu snap stub
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > /etc/apt/preferences.d/mozilla
apt-get update
apt-get install -y --no-install-recommends \
    libayatana-appindicator3-1 \
    libwebkit2gtk-4.1-0 \
    firefox \
    xdg-utils
curl -fsSL -o /tmp/drop-desktop-client.deb \
    "https://github.com/Drop-OSS/drop-app/releases/download/v${DROP_APP_VERSION}/Drop.Desktop.Client_${DROP_APP_VERSION}_amd64.deb"
echo "${DROP_APP_SHA256}  /tmp/drop-desktop-client.deb" | sha256sum -c -
dpkg -i /tmp/drop-desktop-client.deb || apt-get install -f -y
rm -f /tmp/drop-desktop-client.deb
apt-get clean
rm -rf /var/lib/apt/lists/*
_INSTALL_DROP_APP

COPY --chmod=777 scripts/startup.sh /opt/gow/startup-app.sh

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
