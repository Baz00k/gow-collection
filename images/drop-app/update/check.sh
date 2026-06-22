#!/usr/bin/env bash
# Check for drop-app dependency updates
# Checks: Drop release version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

DROP_APP_REPO="${DROP_APP_REPO:-Drop-OSS/drop-app}"

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

get_current_drop_version() {
    get_pin DROP_APP_VERSION
}

fetch_latest_drop_version() {
    local latest_raw
    latest_raw=$(curl -fsSL "https://api.github.com/repos/${DROP_APP_REPO}/releases/latest" | jq -r '.tag_name // empty')
    echo "${latest_raw#v}"  # Strip v prefix
}

# Main
[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

updates=()
summary=""

# Check drop-app
echo "Checking drop-app..."
current_drop=$(get_current_drop_version)
latest_drop=$(fetch_latest_drop_version)

if [[ -n "$latest_drop" ]]; then
    if [[ "$current_drop" != "$latest_drop" ]]; then
        echo "Drop-app update available: $current_drop -> $latest_drop"
        updates+=("drop")
        summary+="### Drop App\n\nUpdated from v${current_drop} to v${latest_drop}.\n\n"
    else
        echo "Drop-app up to date"
    fi
else
    echo "Warning: Could not fetch latest drop-app version"
fi

# Output results
if [[ ${#updates[@]} -gt 0 ]]; then
    echo "update_available=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "update_available=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
