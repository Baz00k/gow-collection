#!/usr/bin/env bash
# Check for Eden updates.
#
# Eden is hosted on its own Forgejo instance, so releases come from the Forgejo
# API instead of GitHub. Only stable releases are tracked (the nightly repo is
# a separate API endpoint); see the README if you want nightlies instead.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

EDEN_API_URL="${EDEN_API_URL:-https://git.eden-emu.dev/api/v1/repos/eden-emu/eden/releases?limit=1}"

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

fetch_latest_version() {
    curl -fsSL "$EDEN_API_URL" | jq -r '.[0].tag_name // empty' | sed 's/^v//'
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

updates=()
summary=""

echo "Checking Eden..."
current_eden=$(get_pin EDEN_VERSION)
latest_eden=$(fetch_latest_version)

if [[ -n "$latest_eden" ]]; then
    if [[ "$current_eden" != "$latest_eden" ]]; then
        echo "Eden update available: $current_eden -> $latest_eden"
        updates+=("eden")
        summary+="### Eden\n\nUpdated from v${current_eden} to v${latest_eden}.\n\n"
    else
        echo "Eden up to date"
    fi
else
    echo "Warning: Could not fetch latest Eden version"
fi

if [[ ${#updates[@]} -gt 0 ]]; then
    echo "update_available=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "update_available=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
