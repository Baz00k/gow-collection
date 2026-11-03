#!/usr/bin/env bash
# Apply base image dependency updates.
# Updates: Fedora base digest (BASE_IMAGE_DIGEST).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
PIN_UPDATES="${PIN_UPDATES:-/dev/stdout}"

source "${SCRIPT_DIR}/lib/base-digest.sh"

abort() { echo "ERROR: $1" >&2; exit 1; }

# Report a new value; update.yml writes it to pins.env once this script succeeds.
pin() { printf '%s=%s\n' "$1" "$2" >> "$PIN_UPDATES"; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

# --- Fedora base digest ---
base_image=$(get_pin BASE_IMAGE)
current_digest=$(get_pin BASE_IMAGE_DIGEST)
latest_digest=$(fetch_remote_digest "$base_image" || true)

if [[ -n "$latest_digest" && "$current_digest" != "$latest_digest" ]]; then
    echo "Updating Fedora base digest: ${current_digest:-none} -> ${latest_digest}"
    pin BASE_IMAGE_DIGEST "${latest_digest}"
fi
