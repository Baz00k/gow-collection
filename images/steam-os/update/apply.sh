#!/usr/bin/env bash
# Apply SteamOS image dependency updates
# Updates: Decky Loader version/URL/SHA256

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

get_decky_repo() {
    local repo
    repo=$(get_pin DECKY_LOADER_REPO)
    echo "${repo:-SteamDeckHomebrew/decky-loader}"
}

fetch_latest_decky_version() {
    local repo
    repo=$(get_decky_repo)
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//'
}

fetch_file_sha256() {
    local url="$1" output_file="$2"
    curl -fsSL "$url" -o "$output_file"
    sha256sum "$output_file" | cut -d' ' -f1
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

# --- Decky Loader ---
decky_repo=$(get_decky_repo)
current_decky=$(get_pin DECKY_LOADER_VERSION)
latest_decky=$(fetch_latest_decky_version)

if [[ -n "$latest_decky" && "$current_decky" != "$latest_decky" ]]; then
    echo "Updating Decky Loader: $current_decky -> $latest_decky"
    decky_url="https://github.com/${decky_repo}/releases/download/v${latest_decky}/PluginLoader"
    echo "Downloading PluginLoader..."
    decky_sha=$(fetch_file_sha256 "$decky_url" /tmp/PluginLoader)
    echo "PluginLoader SHA256: $decky_sha"

    pin DECKY_LOADER_VERSION "${latest_decky}"
    pin DECKY_LOADER_URL "${decky_url}"
    pin DECKY_LOADER_SHA256 "${decky_sha}"

    rm -f /tmp/PluginLoader
fi
