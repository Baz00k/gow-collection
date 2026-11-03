#!/usr/bin/env bash
# Apply prism-offline dependency updates
# Updates: Prism version and AppImage SHA256

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
PIN_UPDATES="${PIN_UPDATES:-/dev/stdout}"

PRISM_REPO="${PRISM_REPO:-Diegiwg/PrismLauncher-Cracked}"

abort() { echo "ERROR: $1" >&2; exit 1; }

# Report a new value; update.yml writes it to pins.env once this script succeeds.
pin() { printf '%s=%s\n' "$1" "$2" >> "$PIN_UPDATES"; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

get_current_prism_version() {
    get_pin PRISM_LAUNCHER_VERSION
}

fetch_latest_prism_version() {
    curl -fsSL "https://api.github.com/repos/${PRISM_REPO}/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//'
}

fetch_appimage_sha256() {
    local url="$1"
    local output_file="$2"
    curl -fsSL "$url" -o "$output_file"
    sha256sum "$output_file" | cut -d' ' -f1
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

current_prism=$(get_current_prism_version)
latest_prism=$(fetch_latest_prism_version)

if [[ -n "$latest_prism" && "$current_prism" != "$latest_prism" ]]; then
    echo "Updating Prism Launcher: $current_prism -> $latest_prism"
    
    base_url="https://github.com/${PRISM_REPO}/releases/download/${latest_prism}"
    x86_64_url="${base_url}/PrismLauncher-Linux-x86_64.AppImage"
    
    echo "Downloading x86_64 AppImage..."
    x86_64_sha=$(fetch_appimage_sha256 "$x86_64_url" /tmp/PrismLauncher-x86_64.AppImage)
    echo "x86_64 SHA256: $x86_64_sha"
    
    pin PRISM_LAUNCHER_VERSION "${latest_prism}"
    pin PRISM_LAUNCHER_APPIMAGE_X86_64_URL "${x86_64_url}"
    pin PRISM_LAUNCHER_APPIMAGE_X86_64_SHA256 "${x86_64_sha}"
    
    rm -f /tmp/PrismLauncher-x86_64.AppImage
fi
