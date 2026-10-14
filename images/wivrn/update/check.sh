#!/usr/bin/env bash
# Check for WiVRn image dependency updates
# Checks: WiVRn server version (client and server versions must match), xrizer version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

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

# --- xrizer ---
echo "Checking xrizer..."
current_xrizer=$(get_pin XRIZER_VERSION)
latest_xrizer=$(fetch_latest_xrizer_version)

if [[ -n "$latest_xrizer" ]]; then
    if [[ "$current_xrizer" != "$latest_xrizer" ]]; then
        echo "xrizer update available: $current_xrizer -> $latest_xrizer"
        updates+=("xrizer")
        summary+="### xrizer\n\nUpdated from v${current_xrizer} to v${latest_xrizer}.\n\n"
    else
        echo "xrizer up to date"
    fi
else
    echo "Warning: Could not fetch latest xrizer version"
fi

if [[ ${#updates[@]} -gt 0 ]]; then
    echo "update_available=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "update_available=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
