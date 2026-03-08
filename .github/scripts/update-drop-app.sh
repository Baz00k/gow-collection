#!/usr/bin/env bash
# Update pins.env with new drop-app version and SHA256

set -euo pipefail

PINS_FILE="${PINS_FILE:?PINS_FILE env var must be set}"
DROP_APP_REPO="${DROP_APP_REPO:-Drop-OSS/drop-app}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

new_version="${1:?Usage: $0 <new-version>}"

# Download .deb and compute checksum
deb_url="https://github.com/${DROP_APP_REPO}/releases/download/v${new_version}/Drop.Desktop.Client_${new_version}_amd64.deb"
echo "Downloading drop-app v${new_version}..."
curl -fsSL -o /tmp/drop-desktop-client.deb "$deb_url"
new_sha256=$(sha256sum /tmp/drop-desktop-client.deb | cut -d' ' -f1)
rm -f /tmp/drop-desktop-client.deb
echo "SHA256: $new_sha256"

# Portable sed (works on both BSD and GNU)
inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

inplace "s|^DROP_APP_VERSION=.*|DROP_APP_VERSION=${new_version}|" "$PINS_FILE"
inplace "s|^DROP_APP_SHA256=.*|DROP_APP_SHA256=${new_sha256}|" "$PINS_FILE"

echo "Updated $PINS_FILE"
cat "$PINS_FILE"

echo "drop_sha256=$new_sha256" >> "$GITHUB_OUTPUT"
