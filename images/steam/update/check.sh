#!/usr/bin/env bash
# Check for steam dependency updates
# Checks: Decky Loader version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

abort() { echo "ERROR: $1" >&2; exit 1; }

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
    if command -v gh &>/dev/null; then
        gh api "repos/${repo}/releases/latest" --jq '.tag_name' | sed 's/^v//'
    else
        curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//'
    fi
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

updates=()
summary=""

# --- Decky Loader ---
echo "Checking Decky Loader..."
current_decky=$(get_pin DECKY_LOADER_VERSION)
latest_decky=$(fetch_latest_decky_version)

if [[ -n "$latest_decky" ]]; then
    if [[ "$current_decky" != "$latest_decky" ]]; then
        echo "Decky Loader update available: $current_decky -> $latest_decky"
        updates+=("decky")
        summary+="### Decky Loader\n\nUpdated from v${current_decky} to v${latest_decky}.\n\n"
    else
        echo "Decky Loader up to date"
    fi
else
    echo "Warning: Could not fetch latest Decky Loader version"
fi

if [[ ${#updates[@]} -gt 0 ]]; then
    echo "update_available=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "update_available=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
