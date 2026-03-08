#!/usr/bin/env bash
# Check for GoW base image updates

set -euo pipefail

PINS_FILE="${PINS_FILE:?PINS_FILE env var must be set}"
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/games-on-whales/base-app}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-edge}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

abort() { echo "ERROR: $1" >&2; exit 1; }

get_current_digest() {
    local full_image
    full_image=$(grep '^BASE_APP_IMAGE=' "$PINS_FILE" | cut -d'=' -f2) || return 1
    [[ -z "$full_image" ]] && return 1
    echo "$full_image" | sed 's/.*@sha256://'
}

fetch_latest_digest() {
    local digest=""

    # crane (most reliable)
    if command -v crane &>/dev/null; then
        digest=$(crane digest "${BASE_IMAGE}:${BASE_IMAGE_TAG}" 2>/dev/null | sed 's/sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    # docker manifest inspect
    if command -v docker &>/dev/null; then
        digest=$(docker manifest inspect "${BASE_IMAGE}:${BASE_IMAGE_TAG}" --verbose 2>/dev/null | \
            jq -r '.[0].Descriptor.digest // .Descriptor.digest // empty' 2>/dev/null | sed 's/sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }

        # pull + inspect fallback
        docker pull "${BASE_IMAGE}:${BASE_IMAGE_TAG}" >/dev/null 2>&1 || true
        digest=$(docker inspect --format='{{index .RepoDigests 0}}' "${BASE_IMAGE}:${BASE_IMAGE_TAG}" 2>/dev/null | \
            sed 's/.*@sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    # GHCR API
    local token manifest
    token=$(curl -fsSL "https://ghcr.io/token?service=ghcr.io&scope=repository:games-on-whales/base-app:pull" 2>/dev/null | jq -r '.token' || true)
    if [[ -n "$token" ]]; then
        manifest=$(curl -fsSL \
            -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
            -H "Authorization: Bearer $token" \
            "https://ghcr.io/v2/games-on-whales/base-app/manifests/${BASE_IMAGE_TAG}" 2>/dev/null || true)
        digest=$(echo "$manifest" | jq -r '.config.digest // empty' 2>/dev/null | sed 's/sha256://' || true)
    fi

    echo "$digest"
}

# Main
[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

current=$(get_current_digest) || abort "Could not read BASE_APP_IMAGE from $PINS_FILE"
echo "Current digest: $current"
echo "current-digest=$current" >> "$GITHUB_OUTPUT"

latest=$(fetch_latest_digest)

if [[ -z "$latest" ]]; then
    echo "Warning: Could not fetch latest digest"
    echo "update-available=false" >> "$GITHUB_OUTPUT"
    echo "new-digest=" >> "$GITHUB_OUTPUT"
    exit 0
fi

echo "Latest digest: $latest"
echo "new-digest=$latest" >> "$GITHUB_OUTPUT"

if [[ "$current" == "$latest" ]]; then
    echo "No update available"
    echo "update-available=false" >> "$GITHUB_OUTPUT"
else
    echo "Update available: ${current:0:12} -> ${latest:0:12}"
    echo "update-available=true" >> "$GITHUB_OUTPUT"
fi
