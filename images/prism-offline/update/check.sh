#!/usr/bin/env bash
# Check for prism-offline dependency updates
# Checks: Prism Launcher release version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

PRISM_REPO="${PRISM_REPO:-Diegiwg/PrismLauncher-Cracked}"

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

get_current_prism_version() {
    get_pin PRISM_LAUNCHER_VERSION
}

fetch_latest_prism_version() {
    if command -v gh &>/dev/null; then
        gh api "repos/${PRISM_REPO}/releases/latest" --jq '.tag_name' | sed 's/^v//'
    else
        curl -fsSL "https://api.github.com/repos/${PRISM_REPO}/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//'
    fi
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

updates=()
summary=""

echo "Checking Prism Launcher..."
current_prism=$(get_current_prism_version)
latest_prism=$(fetch_latest_prism_version)

if [[ -n "$latest_prism" ]]; then
    if [[ "$current_prism" != "$latest_prism" ]]; then
        echo "Prism Launcher update available: $current_prism -> $latest_prism"
        updates+=("prism")
        summary+="### Prism Launcher\n\nUpdated from v${current_prism} to v${latest_prism}.\n\n"
    else
        echo "Prism Launcher up to date"
    fi
else
    echo "Warning: Could not fetch latest Prism Launcher version"
fi

if [[ ${#updates[@]} -gt 0 ]]; then
    echo "update_available=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "update_available=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
