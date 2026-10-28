# syntax=docker/dockerfile:1.4
ARG BASE_APP_IMAGE

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

# The self-extracting AppImage is unpacked at build time; the extracted tree is
# what runs. The bundle carries its own Qt, Vulkan loader, Mesa drivers, FFmpeg,
# SDL, and PulseAudio/ALSA client libraries.
#
# Upstream: https://git.eden-emu.dev/eden-emu/eden
ARG EDEN_VERSION=0.2.1
ARG EDEN_APPIMAGE_URL
ARG EDEN_APPIMAGE_SHA256

RUN set -eux; \
    curl -fsSL "${EDEN_APPIMAGE_URL}" -o /tmp/Eden.AppImage; \
    echo "${EDEN_APPIMAGE_SHA256}  /tmp/Eden.AppImage" | sha256sum -c -; \
    chmod +x /tmp/Eden.AppImage; \
    cd /opt; \
    /tmp/Eden.AppImage --appimage-extract > /dev/null; \
    test -f /opt/squashfs-root/AppRun; \
    # uruntime-based builds extract into AppDir and leave a squashfs-root
    # symlink; plain AppImageKit builds extract into squashfs-root directly. \
    if [ -d /opt/AppDir ]; then mv /opt/AppDir /opt/eden; \
    elif [ -d /opt/squashfs-root ]; then mv /opt/squashfs-root /opt/eden; \
    else echo "unexpected AppImage layout" >&2; exit 1; fi; \
    rm -f /opt/squashfs-root /tmp/Eden.AppImage; \
    test -x /opt/eden/AppRun; \
    test -x /opt/eden/bin/eden; \
    echo "${EDEN_VERSION}" > /opt/eden/.eden-version; \
    # Fail the build if the packaged binary does not match the pinned version. \
    mkdir -p /tmp/eden-version-check; \
    version_output=$(HOME=/tmp/eden-version-check QT_QPA_PLATFORM=offscreen \
        /opt/eden/bin/eden-cli --version); \
    echo "${version_output}"; \
    echo "${version_output}" | grep -F "v${EDEN_VERSION}" > /dev/null; \
    rm -rf /tmp/eden-version-check

# Copy the Eden startup overlay.
COPY --chmod=755 overlay /

ARG IMAGE_SOURCE="https://github.com/Baz00k/gow-collection"

LABEL org.opencontainers.image.description="Eden Nintendo Switch emulator for Games on Whales (Wolf)"
LABEL org.opencontainers.image.authors="Baz00k"
LABEL org.opencontainers.image.title="GoW Eden — gow-collection"
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
LABEL org.opencontainers.image.licenses="GPL-3.0-only"
