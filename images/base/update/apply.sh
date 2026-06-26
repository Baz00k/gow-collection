#!/usr/bin/env bash
# Apply base image dependency updates.
# Updates: Fedora base digest (BASE_IMAGE_DIGEST).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

source "${SCRIPT_DIR}/lib/base-digest.sh"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

applied=false
summary=""

# --- Fedora base digest ---
base_image=$(get_pin BASE_IMAGE)
current_digest=$(get_pin BASE_IMAGE_DIGEST)
latest_digest=$(fetch_remote_digest "$base_image" || true)

if [[ -n "$latest_digest" && "$current_digest" != "$latest_digest" ]]; then
    echo "Updating Fedora base digest: ${current_digest:-none} -> ${latest_digest}"
    inplace "s|^BASE_IMAGE_DIGEST=.*|BASE_IMAGE_DIGEST=${latest_digest}|" "$PINS_FILE"
    applied=true
    summary+="### Fedora Base\n\nUpdated digest to \`${latest_digest}\`.\n\n"
fi

if [[ "$applied" == "true" ]]; then
    echo "Updated $PINS_FILE"
    cat "$PINS_FILE"
    echo "applied=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "No updates to apply"
    echo "applied=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
