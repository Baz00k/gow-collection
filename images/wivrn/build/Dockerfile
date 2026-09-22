# syntax=docker/dockerfile:1.4
ARG BASE_APP_IMAGE

# hadolint ignore=DL3006
FROM ${BASE_APP_IMAGE}

ARG RPMFUSION_FREE_URL
ARG RPMFUSION_FREE_SHA256
ARG RPMFUSION_NONFREE_URL
ARG RPMFUSION_NONFREE_SHA256
ARG WIVRN_VERSION
ARG WIVRN_TARBALL_URL
ARG WIVRN_TARBALL_SHA256

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
# Runtime Packages
# -----------------------------------------------------------------------------
# hadolint ignore=DL3041
RUN <<'_INSTALL_PACKAGES' bash
set -eux

packages=(
    # OpenVR compatibility layer for SteamVR games (the WiVRn server build
    # below does not bundle it; VR_OVERRIDE points games at it at runtime)
    opencomposite

    # Steam client and gaming overlays/performance helpers
    steam
    gamescope
    gamemode
    mangohud

    # PipeWire audio stack: this container replaces Wolf's PulseAudio with
    # PipeWire + WirePlumber so WiVRn can route VR audio to the headset
    pipewire
    pipewire-pulseaudio
    pipewire-utils
    wireplumber

    # mDNS discovery (headset finds the server) and D-Bus runtime
    avahi
    avahi-tools
    dbus-daemon
    dbus-tools
    nss-mdns

    # Shared libraries the source-built WiVRn server links against
    # (proven by ldd closure in the build cleanup step — keep this list
    # tight; anything unused just bloats the Wolf pull)
    boost-iostreams
    ffmpeg-libs
    x264-libs
    libva
    libdrm
    openvr-api
    libarchive
    libnotify
    librsvg2
    libpng
    libbsd

    # General desktop integration helpers used by Steam and launchers
    file
    lsb-release
    xwininfo
    xdg-user-dirs
    xdg-utils
    xz
    zenity
    desktop-file-utils

    # Vulkan diagnostics
    vulkan-tools

    # Fonts
    dejavu-fonts-all
    google-noto-fonts-common

    # Scripting utilities used by init and helper scripts
    jq
    python3
)

dnf install -y --setopt=install_weak_deps=False "${packages[@]}"

dnf clean all
rm -rf /var/cache/dnf
_INSTALL_PACKAGES

# -----------------------------------------------------------------------------
# WiVRn Server (source build)
# -----------------------------------------------------------------------------
# Fedora lags upstream (client and server versions must match), so build the
# pinned release from source. Monado is fetched by CMake at the pinned
# monado-rev commit.
#
# Everything — build-deps install, compile, install, and toolchain removal —
# happens in a SINGLE layer so the ~1GB of headers/compilers never lands in
# the image. A multi-stage builder is not an option: repo policy requires
# exactly one FROM (${BASE_APP_IMAGE}).
# hadolint ignore=DL3041
RUN <<'_BUILD_WIVRN' bash
set -eux

build_packages=(
    cmake
    ninja-build
    gcc-c++
    git
    pkgconf-pkg-config
    vulkan-headers
    vulkan-loader-devel
    glslc
    glslang-devel
    spirv-tools
    spirv-tools-devel
    ffmpeg-devel
    x264-devel
    libdrm-devel
    pipewire-devel
    avahi-devel
    avahi-glib-devel
    eigen3-devel
    json-devel
    cli11-devel
    glib2-devel
    dbus-devel
    libnotify-devel
    librsvg2-devel
    libarchive-devel
    libpng-devel
    openssl-devel
    boost-devel
    openxr-devel
    systemd-devel
    mesa-libEGL-devel
    nv-codec-headers
    bluez-libs-devel
    hidapi-devel
    libusb1-devel
    libuvc-devel
    opencv-devel
    openhmd-devel
    SDL2-devel
    wayland-devel
    wayland-protocols-devel
    libXrandr-devel
    libbsd-devel
    libcap-devel
    cjson-devel
    libjpeg-turbo-devel
    gstreamer1-devel
    gstreamer1-plugins-base-devel
    libva-devel
    librealsense-devel
    openvr-devel
)

dnf install -y --setopt=install_weak_deps=False "${build_packages[@]}"

curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --retry-max-time 60 \
    -o /tmp/wivrn.tar.gz "${WIVRN_TARBALL_URL}"
echo "${WIVRN_TARBALL_SHA256}  /tmp/wivrn.tar.gz" | sha256sum -c -
mkdir -p /tmp/wivrn
tar xzf /tmp/wivrn.tar.gz -C /tmp/wivrn --strip-components=1
rm -f /tmp/wivrn.tar.gz

cmake -S /tmp/wivrn -B /tmp/wivrn/build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    "-DGIT_TAG=v${WIVRN_VERSION}" \
    -DWIVRN_BUILD_CLIENT=OFF \
    -DWIVRN_BUILD_DASHBOARD=OFF \
    -DWIVRN_BUILD_SERVER=ON \
    -DWIVRN_BUILD_WIVRNCTL=ON \
    -DWIVRN_BUILD_TEST=OFF
cmake --build /tmp/wivrn/build
cmake --install /tmp/wivrn/build
rm -rf /tmp/wivrn

/usr/bin/wivrn-server --version | grep -q "${WIVRN_VERSION}"

# Drop the toolchain and headers again, then prove the installed server still
# resolves every shared library (dnf cannot know the source-built binaries
# need them; the survivors are re-pinned as runtime libs above).
dnf remove -y "${build_packages[@]}"

for bin in /usr/bin/wivrn-server /usr/bin/wivrnctl /usr/lib64/wivrn/libopenxr_wivrn.so; do
    if ldd "${bin}" | grep -q 'not found'; then
        echo "Missing shared libraries for ${bin}:"
        ldd "${bin}" | grep 'not found'
        exit 1
    fi
done

/usr/bin/wivrn-server --version

dnf clean all
rm -rf /var/cache/dnf
_BUILD_WIVRN

RUN fc-cache -f -v

# -----------------------------------------------------------------------------
# Overlay (WiVRn session init, startup, and config defaults)
# -----------------------------------------------------------------------------
COPY --chmod=755 overlay /

RUN mkdir -p /usr/games && \
    ln -sf /usr/bin/steam /usr/games/steam && \
    update-desktop-database /usr/share/applications

ARG IMAGE_SOURCE="https://github.com/Baz00k/gow-collection"

LABEL org.opencontainers.image.title="WiVRn + Steam for Games on Whales"
LABEL org.opencontainers.image.description="Native WiVRn VR streaming server with Steam in gamescope for Wolf"
LABEL org.opencontainers.image.authors="Baz00k"
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
LABEL org.opencontainers.image.licenses="GPL-3.0-only"

# ENTRYPOINT is inherited from the base image (/opt/gow/entrypoint.sh).
