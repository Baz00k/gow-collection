# syntax=docker/dockerfile:1.4

# -----------------------------------------------------------------------------
# Stage 1: Build patched bubblewrap
# -----------------------------------------------------------------------------
# Bubblewrap needs patching to work in containers with explicit CAP_SYS_ADMIN.
# The ignore_capabilities.patch removes capability validation that breaks
# when capabilities are explicitly granted (common in container runtimes).
ARG BASE_IMAGE

FROM ${BASE_IMAGE} AS bwrap-builder

ARG BUBBLEWRAP_VERSION
ARG BUBBLEWRAP_COMMIT

WORKDIR /root

# hadolint ignore=DL3008,DL3041
RUN dnf install -y \
    git \
    meson \
    gcc \
    pkgconf-pkg-config \
    patch \
    libcap-devel \
    && dnf clean all \
    && rm -rf /var/cache/dnf

COPY ignore_capabilities.patch /root/

RUN git clone --depth=1 https://github.com/containers/bubblewrap.git -b ${BUBBLEWRAP_VERSION} && \
    cd bubblewrap && \
    test "$(git rev-parse HEAD)" = "${BUBBLEWRAP_COMMIT}" || \
        { echo "ERROR: bubblewrap commit mismatch! Expected ${BUBBLEWRAP_COMMIT}, got $(git rev-parse HEAD)"; exit 1; } && \
    patch -p1 < ../ignore_capabilities.patch && \
    meson _builddir && \
    meson compile -C _builddir

# -----------------------------------------------------------------------------
# Stage 2: Main Steam environment
# -----------------------------------------------------------------------------
FROM ${BASE_IMAGE}

ARG RPMFUSION_FREE_URL
ARG RPMFUSION_NONFREE_URL
ARG DECKY_LOADER_VERSION
ARG DECKY_LOADER_URL
ARG DECKY_LOADER_SHA256
ARG UMU_LAUNCHER_VERSION
ARG UMU_LAUNCHER_URL
ARG UMU_LAUNCHER_SHA256

# -----------------------------------------------------------------------------
# RPM Fusion Setup
# -----------------------------------------------------------------------------
# Steam is in RPM Fusion nonfree repository. Must enable both free and nonfree.
# hadolint ignore=DL3041
RUN dnf install -y \
    ${RPMFUSION_FREE_URL} \
    ${RPMFUSION_NONFREE_URL}

# -----------------------------------------------------------------------------
# Package Installation
# -----------------------------------------------------------------------------
# hadolint ignore=DL3041
RUN dnf install -y \
    steam \
    gamescope \
    mangohud \
    gamemode \
    dbus-daemon \
    NetworkManager \
    bluez \
    ibus \
    curl \
    xz \
    zenity \
    file \
    xdg-user-dirs \
    xdg-utils \
    pciutils \
    mesa-demos \
    vulkan-tools \
    dejavu-fonts-all \
    google-noto-fonts-common \
    python3 \
    jq \
    && dnf clean all \
    && rm -rf /var/cache/dnf

# -----------------------------------------------------------------------------
# UMU Launcher
# -----------------------------------------------------------------------------
RUN curl -fsSL -o /tmp/umu-launcher.rpm "${UMU_LAUNCHER_URL}" && \
    echo "${UMU_LAUNCHER_SHA256}  /tmp/umu-launcher.rpm" | sha256sum -c - && \
    dnf install -y /tmp/umu-launcher.rpm && \
    rm -f /tmp/umu-launcher.rpm && \
    dnf clean all

# -----------------------------------------------------------------------------
# Decky Loader
# -----------------------------------------------------------------------------
RUN mkdir -p /opt/decky && \
    curl -fsSL -o /opt/decky/PluginLoader "${DECKY_LOADER_URL}" && \
    echo "${DECKY_LOADER_SHA256}  /opt/decky/PluginLoader" | sha256sum -c - && \
    chmod +x /opt/decky/PluginLoader

# -----------------------------------------------------------------------------
# gosu — privilege dropping tool
# -----------------------------------------------------------------------------
ARG TARGETARCH
ARG GOSU_AMD64_URL
ARG GOSU_AMD64_SHA256

RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        curl -fsSL -o /usr/bin/gosu "${GOSU_AMD64_URL}" && \
        echo "${GOSU_AMD64_SHA256}  /usr/bin/gosu" | sha256sum -c - && \
        chmod +x /usr/bin/gosu; \
    else \
        echo "Unsupported architecture: $ARCH" >&2 && \
        exit 1; \
    fi

# -----------------------------------------------------------------------------
# System Configuration
# -----------------------------------------------------------------------------
RUN touch /etc/NetworkManager/conf.d/10-globally-managed-devices.conf

RUN fc-cache -f -v

# Wolf mounts NVIDIA drivers at /usr/nvidia — pre-configure linker search paths
# Vulkan ICD and EGL configs are copied at runtime by /etc/cont-init.d/10-nvidia.sh
RUN printf '%s\n' '/usr/nvidia/lib' '/usr/nvidia/lib32' > /etc/ld.so.conf.d/nvidia.conf

RUN ln -sf /home/retro /home/deck

# -----------------------------------------------------------------------------
# Overlay and bwrap
# -----------------------------------------------------------------------------
COPY --chmod=755 overlay /
COPY --from=bwrap-builder --chmod=755 /root/bubblewrap/_builddir/bwrap /usr/bin/bwrap

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

# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------
ENTRYPOINT ["/opt/gow/entrypoint.sh"]
