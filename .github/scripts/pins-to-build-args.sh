#!/usr/bin/env bash
# Convert an image's build/pins.env into newline-separated KEY=VALUE build-args.
#
# Usage:
#   pins-to-build-args.sh <image-dir> [BASE_APP_IMAGE_OVERRIDE]
#
# Prints build-args to stdout. When an override is given, BASE_APP_IMAGE from
# pins.env is replaced with the override (used by the base-graph validation path
# to build apps against a locally-built base instead of the committed digest).
#
# Always appends IMAGE_SOURCE so Dockerfile OCI labels resolve consistently.

set -euo pipefail

IMAGE_DIR="${1:?image dir required}"
BASE_APP_IMAGE_OVERRIDE="${2:-}"
IMAGE_SOURCE="${IMAGE_SOURCE:-https://github.com/${GITHUB_REPOSITORY:-Baz00k/gow-collection}}"

PINS_FILE="${IMAGE_DIR}/build/pins.env"
if [[ ! -f "$PINS_FILE" ]]; then
    echo "ERROR: ${PINS_FILE} not found" >&2
    exit 1
fi

while IFS='=' read -r key value; do
    # Skip comments and blank lines.
    [[ -z "$key" || "$key" == \#* ]] && continue
    # Strip surrounding double quotes if present.
    value="${value%\"}"
    value="${value#\"}"
    if [[ "$key" == "BASE_APP_IMAGE" && -n "$BASE_APP_IMAGE_OVERRIDE" ]]; then
        value="$BASE_APP_IMAGE_OVERRIDE"
    fi
    printf '%s=%s\n' "$key" "$value"
done < "$PINS_FILE"

printf 'IMAGE_SOURCE=%s\n' "$IMAGE_SOURCE"
