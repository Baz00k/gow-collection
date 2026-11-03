#!/usr/bin/env bash
# Apply WiVRn image dependency updates
# Updates: WiVRn server version/tarball URL/SHA256, xrizer version/ZIP URL/SHA256/vrclient.so SHA256

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
PIN_UPDATES="${PIN_UPDATES:-/dev/stdout}"

abort() { echo "ERROR: $1" >&2; exit 1; }

# Report a new value; update.yml writes it to pins.env once this script succeeds.
pin() { printf '%s=%s\n' "$1" "$2" >> "$PIN_UPDATES"; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

get_xrizer_repo() {
    local repo
    repo=$(get_pin XRIZER_REPO)
    echo "${repo:-Supreeeme/xrizer}"
}

get_wivrn_repo() {
    local repo
    repo=$(get_pin WIVRN_REPO)
    echo "${repo:-WiVRn/WiVRn}"
}

fetch_latest_wivrn_version() {
    local repo
    repo=$(get_wivrn_repo)
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//'
}

fetch_latest_xrizer_version() {
    local repo
    repo=$(get_xrizer_repo)
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//'
}

fetch_file_sha256() {
    local url="$1" output_file="$2"
    curl -fsSL "$url" -o "$output_file"
    sha256sum "$output_file" | cut -d' ' -f1
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

# --- WiVRn server ---
wivrn_repo=$(get_wivrn_repo)
current_wivrn=$(get_pin WIVRN_VERSION)
latest_wivrn=$(fetch_latest_wivrn_version)

if [[ -n "$latest_wivrn" && "$current_wivrn" != "$latest_wivrn" ]]; then
    echo "Updating WiVRn: $current_wivrn -> $latest_wivrn"
    wivrn_url="https://github.com/${wivrn_repo}/archive/refs/tags/v${latest_wivrn}.tar.gz"
    echo "Downloading WiVRn source tarball..."
    wivrn_sha=$(fetch_file_sha256 "$wivrn_url" /tmp/wivrn.tar.gz)
    echo "WiVRn tarball SHA256: $wivrn_sha"

    pin WIVRN_VERSION "${latest_wivrn}"
    pin WIVRN_TARBALL_URL "${wivrn_url}"
    pin WIVRN_TARBALL_SHA256 "${wivrn_sha}"

    rm -f /tmp/wivrn.tar.gz
fi

# --- xrizer ---
xrizer_repo=$(get_xrizer_repo)
current_xrizer=$(get_pin XRIZER_VERSION)
latest_xrizer=$(fetch_latest_xrizer_version)

if [[ -n "$latest_xrizer" && "$current_xrizer" != "$latest_xrizer" ]]; then
    echo "Updating xrizer: $current_xrizer -> $latest_xrizer"
    xrizer_url="https://github.com/${xrizer_repo}/releases/download/v${latest_xrizer}/xrizer-v${latest_xrizer}.zip"
    echo "Downloading xrizer release ZIP..."
    xrizer_sha=$(fetch_file_sha256 "$xrizer_url" /tmp/xrizer.zip)
    echo "xrizer ZIP SHA256: $xrizer_sha"
    # Same member the Dockerfile installs.
    xrizer_vrclient_sha=$(unzip -p /tmp/xrizer.zip "xrizer-v${latest_xrizer}/bin/linux64/vrclient.so" | sha256sum | cut -d' ' -f1)
    echo "xrizer vrclient.so SHA256: $xrizer_vrclient_sha"

    pin XRIZER_VERSION "${latest_xrizer}"
    pin XRIZER_ZIP_URL "${xrizer_url}"
    pin XRIZER_ZIP_SHA256 "${xrizer_sha}"
    pin XRIZER_VRCLIENT_SHA256 "${xrizer_vrclient_sha}"

    rm -f /tmp/xrizer.zip
fi
