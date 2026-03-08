#!/usr/bin/env bash
# Update pins.env with new Prism Launcher version and checksums

set -euo pipefail

PINS_FILE="${PINS_FILE:?PINS_FILE env var must be set}"
PRISM_REPO="${PRISM_REPO:-Diegiwg/PrismLauncher-Cracked}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

new_version="${1:?Usage: $0 <new-version>}"

base_url="https://github.com/${PRISM_REPO}/releases/download/${new_version}"

x86_64_url="${base_url}/PrismLauncher-Linux-x86_64.AppImage"
aarch64_url="${base_url}/PrismLauncher-Linux-aarch64.AppImage"

echo "Downloading x86_64 AppImage..."
curl -fsSL "$x86_64_url" -o /tmp/PrismLauncher-x86_64.AppImage
x86_64_sha=$(sha256sum /tmp/PrismLauncher-x86_64.AppImage | cut -d' ' -f1)
echo "x86_64 SHA256: $x86_64_sha"

echo "Downloading aarch64 AppImage..."
curl -fsSL "$aarch64_url" -o /tmp/PrismLauncher-aarch64.AppImage
aarch64_sha=$(sha256sum /tmp/PrismLauncher-aarch64.AppImage | cut -d' ' -f1)
echo "aarch64 SHA256: $aarch64_sha"

# Update pins.env (portable across BSD/GNU sed)
inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

inplace "s|^PRISM_LAUNCHER_VERSION=.*|PRISM_LAUNCHER_VERSION=${new_version}|" "$PINS_FILE"
inplace "s|^PRISM_LAUNCHER_APPIMAGE_X86_64_URL=.*|PRISM_LAUNCHER_APPIMAGE_X86_64_URL=${x86_64_url}|" "$PINS_FILE"
inplace "s|^PRISM_LAUNCHER_APPIMAGE_X86_64_SHA256=.*|PRISM_LAUNCHER_APPIMAGE_X86_64_SHA256=${x86_64_sha}|" "$PINS_FILE"
inplace "s|^PRISM_LAUNCHER_APPIMAGE_AARCH64_URL=.*|PRISM_LAUNCHER_APPIMAGE_AARCH64_URL=${aarch64_url}|" "$PINS_FILE"
inplace "s|^PRISM_LAUNCHER_APPIMAGE_AARCH64_SHA256=.*|PRISM_LAUNCHER_APPIMAGE_AARCH64_SHA256=${aarch64_sha}|" "$PINS_FILE"

echo "Updated $PINS_FILE"
cat "$PINS_FILE"

# Output checksums for PR body
echo "prism_x86_64_sha=$x86_64_sha" >> "$GITHUB_OUTPUT"
echo "prism_aarch64_sha=$aarch64_sha" >> "$GITHUB_OUTPUT"
