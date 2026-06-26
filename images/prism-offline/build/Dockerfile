# syntax=docker/dockerfile:1.4
ARG BASE_APP_IMAGE

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

# hadolint ignore=DL3041
RUN <<_INSTALL_PACKAGES
set -eux

# TLS and download tooling used to fetch pinned JRE and AppImage artifacts
dnf install -y \
    ca-certificates \
    curl

# Archive tooling required to unpack Temurin JRE tarballs
dnf install -y \
    bsdtar \
    gzip

dnf clean all
rm -rf /var/cache/dnf
_INSTALL_PACKAGES

# Bundled Temurin JREs required for different Minecraft versions:
# - Java 21: Minecraft 1.21+
# - Java 17: Minecraft 1.18 - 1.20.4
# - Java 8:  Minecraft 1.16 and below
# These are app-owned pins instead of Fedora packages to avoid distro package drift.
ARG TEMURIN_JRE_8_X86_64_URL
ARG TEMURIN_JRE_8_X86_64_SHA256
ARG TEMURIN_JRE_17_X86_64_URL
ARG TEMURIN_JRE_17_X86_64_SHA256
ARG TEMURIN_JRE_21_X86_64_URL
ARG TEMURIN_JRE_21_X86_64_SHA256

RUN set -eux; \
    mkdir -p /opt/java; \
    for version in 8 17 21; do \
        eval "url=\${TEMURIN_JRE_${version}_X86_64_URL}"; \
        eval "sha256=\${TEMURIN_JRE_${version}_X86_64_SHA256}"; \
        curl -fsSL "${url}" -o "/tmp/temurin-jre-${version}.tar.gz"; \
        echo "${sha256}  /tmp/temurin-jre-${version}.tar.gz" | sha256sum -c -; \
        mkdir -p "/opt/java/${version}"; \
        bsdtar -xzf "/tmp/temurin-jre-${version}.tar.gz" -C "/opt/java/${version}" --strip-components=1; \
        test -x "/opt/java/${version}/bin/java"; \
        rm -f "/tmp/temurin-jre-${version}.tar.gz"; \
    done; \
    ln -sf /opt/java/21/bin/java /usr/local/bin/java

# Install Prism Launcher (Offline-Enabled Fork)
# Using Diegiwg/PrismLauncher-Cracked AppImage for portability
# This fork removes the MSA gate check, enabling offline account creation
# without requiring a Microsoft account first.
#
# See: https://github.com/Diegiwg/PrismLauncher-Cracked
ARG PRISM_LAUNCHER_VERSION=10.0.5
ARG PRISM_LAUNCHER_APPIMAGE_X86_64_URL
ARG PRISM_LAUNCHER_APPIMAGE_X86_64_SHA256

RUN set -eux; \
    mkdir -p /opt/prismlauncher; \
    curl -fsSL "${PRISM_LAUNCHER_APPIMAGE_X86_64_URL}" -o /opt/prismlauncher/PrismLauncher.AppImage; \
    echo "${PRISM_LAUNCHER_APPIMAGE_X86_64_SHA256}  /opt/prismlauncher/PrismLauncher.AppImage" | sha256sum -c -; \
    chmod +x /opt/prismlauncher/PrismLauncher.AppImage; \
    cd /opt/prismlauncher; \
    ./PrismLauncher.AppImage --appimage-extract > /dev/null; \
    test -f /opt/prismlauncher/squashfs-root/AppRun; \
    chmod +x /opt/prismlauncher/squashfs-root/AppRun; \
    test -x /opt/prismlauncher/squashfs-root/AppRun; \
    # Create symlink so 'prismlauncher' is in PATH \
    ln -sf /opt/prismlauncher/squashfs-root/AppRun /usr/local/bin/prismlauncher

# Copy Prism-specific startup overlay.
COPY --chmod=755 overlay /

# XDG_RUNTIME_DIR is required for Wayland compositor integration
# Wolf sets up /tmp/.X11-unix for X11 socket forwarding

ENV XDG_RUNTIME_DIR=/tmp/.X11-unix

ARG IMAGE_SOURCE="https://github.com/Baz00k/gow-collection"

LABEL org.opencontainers.image.description="Prism Launcher with offline account support for Games on Whales (Wolf)"
LABEL org.opencontainers.image.authors="Baz00k"
LABEL org.opencontainers.image.title="GoW Prism Launcher (Offline-Enabled) — gow-collection"
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
LABEL org.opencontainers.image.licenses="GPL-3.0-only"
