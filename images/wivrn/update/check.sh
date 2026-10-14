#!/usr/bin/env bash
# Check for WiVRn image dependency updates
# Checks: WiVRn server version (client and server versions must match), xrizer

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
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

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

updates=()
summary=""

# --- WiVRn server ---
echo "Checking WiVRn server..."
current_wivrn=$(get_pin WIVRN_VERSION)
latest_wivrn=$(fetch_latest_wivrn_version)

if [[ -n "$latest_wivrn" ]]; then
    if [[ "$current_wivrn" != "$latest_wivrn" ]]; then
        echo "WiVRn update available: $current_wivrn -> $latest_wivrn"
        updates+=("wivrn")
        summary+="### WiVRn\n\nUpdated from v${current_wivrn} to v${latest_wivrn}.\n\n"
    else
        echo "WiVRn up to date"
    fi
else
    echo "Warning: Could not fetch latest WiVRn version"
fi

echo "Checking xrizer..."
xrizer_repo=$(get_pin XRIZER_REPO)
xrizer_repo="${xrizer_repo:-Supreeeme/xrizer}"
current_xrizer=$(get_pin XRIZER_VERSION)
xrizer_release=$(curl -fsSL "https://api.github.com/repos/${xrizer_repo}/releases/latest")
latest_xrizer=$(jq -er '.tag_name | select(type == "string" and length > 0)' <<< "$xrizer_release")
latest_xrizer="${latest_xrizer#v}"
[[ "$latest_xrizer" =~ ^[0-9]+(\.[0-9]+)*$ ]] || abort "Unsupported xrizer version: $latest_xrizer"
# Only advertise releases with the runtime ZIP this Dockerfile can consume.
jq -e --arg asset "xrizer-v${latest_xrizer}.zip" \
    '[.assets[] | select(.name == $asset)] | length == 1' <<< "$xrizer_release" >/dev/null \
    || abort "xrizer release v${latest_xrizer} has no unique runtime ZIP"
if [[ "$current_xrizer" != "$latest_xrizer" ]]; then
    echo "xrizer update available: $current_xrizer -> $latest_xrizer"
    updates+=("xrizer")
    summary+="### xrizer\n\nUpdated from v${current_xrizer} to v${latest_xrizer}.\n\n"
else
    echo "xrizer up to date"
fi

if [[ ${#updates[@]} -gt 0 ]]; then
    echo "update_available=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "update_available=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
