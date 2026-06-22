#!/usr/bin/env bash
# Check for steam dependency updates
# Checks: Decky Loader version, Bubblewrap version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${SCRIPT_DIR}/../build/pins.env"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

abort() { echo "ERROR: $1" >&2; exit 1; }

get_current_decky_version() {
    grep '^DECKY_LOADER_VERSION=' "$PINS_FILE" | cut -d'=' -f2 || echo ""
}

get_decky_repo() {
    grep '^DECKY_LOADER_REPO=' "$PINS_FILE" | cut -d'=' -f2 || echo "SteamDeckHomebrew/decky-loader"
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

get_current_bwrap_version() {
    grep '^BUBBLEWRAP_VERSION=' "$PINS_FILE" | cut -d'=' -f2 || echo ""
}

get_bwrap_repo() {
    grep '^BUBBLEWRAP_REPO=' "$PINS_FILE" | cut -d'=' -f2 || echo "containers/bubblewrap"
}

fetch_latest_bwrap_version() {
    local repo
    repo=$(get_bwrap_repo)
    if command -v gh &>/dev/null; then
        gh api "repos/${repo}/releases/latest" --jq '.tag_name'
    else
        curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty'
    fi
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

updates=()
summary=""

echo "Checking Decky Loader..."
current_decky=$(get_current_decky_version)
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

echo "Checking Bubblewrap..."
current_bwrap=$(get_current_bwrap_version)
latest_bwrap=$(fetch_latest_bwrap_version)

if [[ -n "$latest_bwrap" ]]; then
    if [[ "$current_bwrap" != "$latest_bwrap" ]]; then
        echo "Bubblewrap update available: ${current_bwrap} -> ${latest_bwrap}"
        updates+=("bwrap")
        summary+="### Bubblewrap\n\nUpdated from ${current_bwrap} to ${latest_bwrap}.\n\n"
    else
        echo "Bubblewrap up to date"
    fi
else
    echo "Warning: Could not fetch latest Bubblewrap version"
fi

if [[ ${#updates[@]} -gt 0 ]]; then
    echo "update_available=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "update_available=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
