# =============================================================================
# GoW Prism Launcher Offline-Enabled Image
# =============================================================================
# This Dockerfile creates a Games on Whales (Wolf) compatible container image
# with Prism Launcher and offline account support.
#
# REPRODUCIBILITY: This image is built with deterministic practices:
# - Base image pinned to digest in build/pins.env
# - All downloads verified via SHA256 checksums
# - No timestamps or random values in build
# - Minimal layers with cleanup in same RUN instruction
#
# Build: docker build --build-arg BASE_APP_IMAGE=ghcr.io/games-on-whales/base-app:edge@sha256:xxx -t gow-prism-offline .
# =============================================================================

ARG BASE_APP_IMAGE

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# =============================================================================
# Install Java Runtimes
# =============================================================================
# Java versions required for different Minecraft versions:
# - Java 21: Minecraft 1.21+
# - Java 17: Minecraft 1.18 - 1.20.4
# - Java 8:  Minecraft 1.16 and below

ARG REQUIRED_PACKAGES=" \
    ca-certificates \
    curl \
    openjdk-21-jre \
    openjdk-17-jre \
    openjdk-8-jre \
    "

RUN apt-get update && \
    apt-get install -y --no-install-recommends $REQUIRED_PACKAGES && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# =============================================================================
# Install Prism Launcher (Offline-Enabled Fork)
# =============================================================================
# Using Diegiwg/PrismLauncher-Cracked AppImage for portability
# This fork removes the MSA gate check, enabling offline account creation
# without requiring a Microsoft account first.
#
# See: https://github.com/Diegiwg/PrismLauncher-Cracked
# =============================================================================

# Build args for Prism Launcher AppImage URLs and checksums
# These are sourced from build/pins.env for reproducibility
ARG PRISM_LAUNCHER_VERSION=10.0.5
ARG PRISM_LAUNCHER_APPIMAGE_X86_64_URL
ARG PRISM_LAUNCHER_APPIMAGE_X86_64_SHA256
ARG PRISM_LAUNCHER_APPIMAGE_AARCH64_URL
ARG PRISM_LAUNCHER_APPIMAGE_AARCH64_SHA256

# TARGETARCH is automatically set by Docker BuildKit (amd64 or arm64)
ARG TARGETARCH

# Install Prism Launcher AppImage
# Downloads the appropriate AppImage for the target architecture,
RUN set -eux; \
    # Select the correct AppImage URL and checksum based on architecture \
    case "${TARGETARCH}" in \
        amd64) \
            APPIMAGE_URL="${PRISM_LAUNCHER_APPIMAGE_X86_64_URL}"; \
            APPIMAGE_SHA256="${PRISM_LAUNCHER_APPIMAGE_X86_64_SHA256}"; \
            ;; \
        arm64) \
            APPIMAGE_URL="${PRISM_LAUNCHER_APPIMAGE_AARCH64_URL}"; \
            APPIMAGE_SHA256="${PRISM_LAUNCHER_APPIMAGE_AARCH64_SHA256}"; \
            ;; \
        *) \
            echo "Unsupported architecture: ${TARGETARCH}"; \
            exit 1; \
            ;; \
    esac; \
    # Create installation directory \
    mkdir -p /opt/prismlauncher; \
    # Download the AppImage \
    curl -fsSL "${APPIMAGE_URL}" -o /opt/prismlauncher/PrismLauncher.AppImage; \
    # Verify SHA256 checksum for supply chain integrity \
    echo "${APPIMAGE_SHA256}  /opt/prismlauncher/PrismLauncher.AppImage" | sha256sum -c -; \
    # Make executable \
    chmod +x /opt/prismlauncher/PrismLauncher.AppImage; \
    cd /opt/prismlauncher; \
    ./PrismLauncher.AppImage --appimage-extract > /dev/null; \
    test -f /opt/prismlauncher/squashfs-root/AppRun; \
    chmod +x /opt/prismlauncher/squashfs-root/AppRun; \
    test -x /opt/prismlauncher/squashfs-root/AppRun; \
    # Create symlink so 'prismlauncher' is in PATH \
    ln -sf /opt/prismlauncher/squashfs-root/AppRun /usr/local/bin/prismlauncher

# =============================================================================
# Startup Script
# =============================================================================
# Copy the Wolf-compatible startup script that launches Prism Launcher
# through the GoW compositor helper.

COPY --chmod=755 scripts/startup.sh /opt/gow/startup-app.sh

# =============================================================================
# Environment Variables
# =============================================================================
# XDG_RUNTIME_DIR is required for Wayland compositor integration
# Wolf sets up /tmp/.X11-unix for X11 socket forwarding

ENV XDG_RUNTIME_DIR=/tmp/.X11-unix

# =============================================================================
# OCI Image Labels
# =============================================================================
# Standard OCI labels for image metadata and provenance
# See: https://github.com/opencontainers/image-spec/blob/main/annotations.md

ARG IMAGE_SOURCE="https://github.com/Baz00k/gow-collection"
ARG IMAGE_DESCRIPTION="Prism Launcher with offline account support for Games on Whales (Wolf)"
ARG IMAGE_AUTHORS="Baz00k"

LABEL org.opencontainers.image.source="${IMAGE_SOURCE}"
LABEL org.opencontainers.image.description="${IMAGE_DESCRIPTION}"
LABEL org.opencontainers.image.authors="${IMAGE_AUTHORS}"
LABEL org.opencontainers.image.title="GoW Prism Launcher (Offline-Enabled) — gow-collection"
LABEL org.opencontainers.image.licenses="GPL-3.0-only"
