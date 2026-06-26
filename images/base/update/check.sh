#!/usr/bin/env bash
# Check for base image dependency updates.
# Checks: Fedora base digest (rolling tag -> digest).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

source "${SCRIPT_DIR}/lib/base-digest.sh"

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

updates=()
summary=""

# --- Fedora base digest ---
echo "Checking Fedora base image digest..."
base_image=$(get_pin BASE_IMAGE)
current_digest=$(get_pin BASE_IMAGE_DIGEST)
[[ -z "$base_image" ]] && abort "BASE_IMAGE not set in $PINS_FILE"

latest_digest=$(fetch_remote_digest "$base_image" || true)

if [[ -n "$latest_digest" ]]; then
    if [[ "$current_digest" != "$latest_digest" ]]; then
        echo "Base image update available: ${current_digest:-none} -> ${latest_digest}"
        updates+=("base")
        summary+="### Fedora Base\n\n| Field | Value |\n|-------|-------|\n| Tag | \`${base_image}\` |\n| Previous | \`${current_digest:-none}\` |\n| New | \`${latest_digest}\` |\n\n"
    else
        echo "Base image up to date"
    fi
else
    echo "Warning: Could not resolve latest digest for ${base_image}"
fi

if [[ ${#updates[@]} -gt 0 ]]; then
    echo "update_available=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "update_available=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
