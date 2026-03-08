#!/usr/bin/env bash
# Update pins.env with new base image digest

set -euo pipefail

PINS_FILE="${PINS_FILE:?PINS_FILE env var must be set}"
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/games-on-whales/base-app}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-edge}"

new_digest="${1:?Usage: $0 <new-digest>}"

new_image="${BASE_IMAGE}:${BASE_IMAGE_TAG}@sha256:${new_digest}"
echo "Updating base image to: $new_image"

# Portable sed (works on both BSD and GNU)
sed "s|^BASE_APP_IMAGE=.*|BASE_APP_IMAGE=${new_image}|" "$PINS_FILE" > "${PINS_FILE}.tmp" && mv "${PINS_FILE}.tmp" "$PINS_FILE"

echo "Updated $PINS_FILE"
cat "$PINS_FILE"
