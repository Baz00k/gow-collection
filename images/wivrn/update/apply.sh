#!/usr/bin/env bash
# Apply WiVRn image dependency updates
# Updates: WiVRn server version/tarball URL/SHA256, xrizer version/ZIP URL/SHA256/vrclient.so SHA256

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

abort() { echo "ERROR: $1" >&2; exit 1; }

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

applied=false
summary=""

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

    inplace "s|^WIVRN_VERSION=.*|WIVRN_VERSION=${latest_wivrn}|" "$PINS_FILE"
    inplace "s|^WIVRN_TARBALL_URL=.*|WIVRN_TARBALL_URL=${wivrn_url}|" "$PINS_FILE"
    inplace "s|^WIVRN_TARBALL_SHA256=.*|WIVRN_TARBALL_SHA256=${wivrn_sha}|" "$PINS_FILE"

    rm -f /tmp/wivrn.tar.gz
    applied=true
    summary+="### WiVRn\n\nUpdated from v${current_wivrn} to v${latest_wivrn}.\n\n"
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

    inplace "s|^XRIZER_VERSION=.*|XRIZER_VERSION=${latest_xrizer}|" "$PINS_FILE"
    inplace "s|^XRIZER_ZIP_URL=.*|XRIZER_ZIP_URL=${xrizer_url}|" "$PINS_FILE"
    inplace "s|^XRIZER_ZIP_SHA256=.*|XRIZER_ZIP_SHA256=${xrizer_sha}|" "$PINS_FILE"
    inplace "s|^XRIZER_VRCLIENT_SHA256=.*|XRIZER_VRCLIENT_SHA256=${xrizer_vrclient_sha}|" "$PINS_FILE"

    rm -f /tmp/xrizer.zip
    applied=true
    summary+="### xrizer\n\nUpdated from v${current_xrizer} to v${latest_xrizer}.\n\n"
fi

if [[ "$applied" == "true" ]]; then
    echo "Updated $PINS_FILE"
    cat "$PINS_FILE"
    echo "applied=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "No updates to apply"
    echo "applied=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
