# syntax=docker/dockerfile:1.4

# -----------------------------------------------------------------------------
# Shared Fedora base for the gow-collection images.
# -----------------------------------------------------------------------------
# Provides the common Games on Whales runtime contract that every app image in
# this repo builds on:
#   - runtime user creation + gosu privilege-drop handoff (entrypoint.sh)
#   - /etc/cont-init.d/* init-script runner (user, devices, NVIDIA)
#   - shared logging + performance-tuning helpers
#   - patched bubblewrap for container-friendly sandboxing
#
# App images set BASE_APP_IMAGE to a pinned digest of this image and only add
# their own application packages + startup script on top.
# -----------------------------------------------------------------------------
ARG BASE_IMAGE
ARG BASE_IMAGE_DIGEST

# -----------------------------------------------------------------------------
# Stage 1: Build patched bubblewrap
# -----------------------------------------------------------------------------
# Bubblewrap needs patching to work in containers with explicit CAP_SYS_ADMIN.
# The ignore_capabilities.patch removes capability validation that breaks
# when capabilities are explicitly granted (common in container runtimes).
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}@${BASE_IMAGE_DIGEST} AS bwrap-builder

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
# Stage 2: Base runtime
# -----------------------------------------------------------------------------
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}@${BASE_IMAGE_DIGEST}

# -----------------------------------------------------------------------------
# Shared runtime packages
# -----------------------------------------------------------------------------
# These are the packages the shared cont-init/entrypoint scripts rely on:
#   shadow-utils  — useradd/groupadd/usermod
#   util-linux    — getent and friends
#   procps-ng     — pgrep / sysctl (performance tuning, diagnostics)
#   findutils     — find (diagnostics)
#   libcap        — runtime cap for the patched bwrap
# hadolint ignore=DL3041
RUN dnf install -y \
    bash \
    coreutils \
    shadow-utils \
    util-linux \
    procps-ng \
    findutils \
    libcap \
    curl \
    fontconfig \
    glibc-langpack-en \
    && dnf clean all \
    && rm -rf /var/cache/dnf

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
# NVIDIA linker search paths
# -----------------------------------------------------------------------------
# Wolf mounts NVIDIA drivers at /usr/nvidia — pre-configure linker search paths.
# Vulkan ICD and EGL configs are copied at runtime by 30-nvidia.sh.
RUN printf '%s\n' '/usr/nvidia/lib' '/usr/nvidia/lib32' > /etc/ld.so.conf.d/nvidia.conf

# Build-time /home/deck -> /home/retro convenience symlink. 10-setup-user.sh
# re-points it at runtime if UHOME differs from the default.
RUN ln -sf /home/retro /home/deck

# -----------------------------------------------------------------------------
# Shared overlay (entrypoint, logging, cont-init scripts) and patched bwrap
# -----------------------------------------------------------------------------
COPY --chmod=755 overlay /
COPY --from=bwrap-builder --chmod=755 /root/bubblewrap/_builddir/bwrap /usr/bin/bwrap

# -----------------------------------------------------------------------------
# Environment and Labels
# -----------------------------------------------------------------------------
ENV XDG_RUNTIME_DIR=/tmp/.X11-unix
ENV LANG=C.UTF-8

ARG IMAGE_SOURCE="https://github.com/Baz00k/gow-collection"

LABEL org.opencontainers.image.title="Base image for gow-collection (Fedora)"
LABEL org.opencontainers.image.description="Shared Fedora base with the Games on Whales runtime contract (user setup, gosu handoff, cont-init, bubblewrap)"
LABEL org.opencontainers.image.authors="Baz00k"
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
LABEL org.opencontainers.image.licenses="GPL-3.0-only"

# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------
ENTRYPOINT ["/opt/gow/entrypoint.sh"]
