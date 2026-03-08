#!/usr/bin/env bash
# Check for drop-app dependency updates
# Checks: BASE_APP_IMAGE digest, Drop release version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${SCRIPT_DIR}/../build/pins.env"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

BASE_IMAGE="${BASE_IMAGE:-ghcr.io/games-on-whales/base-app}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-edge}"
DROP_APP_REPO="${DROP_APP_REPO:-Drop-OSS/drop-app}"

# Portable in-place sed
inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

abort() { echo "ERROR: $1" >&2; exit 1; }

get_current_base_digest() {
    local full_image
    full_image=$(grep '^BASE_APP_IMAGE=' "$PINS_FILE" | cut -d'=' -f2) || return 1
    [[ -z "$full_image" ]] && return 1
    echo "$full_image" | sed 's/.*@sha256://'
}

fetch_latest_base_digest() {
    local digest=""

    # GHCR API (most reliable in CI)
    local token manifest
    token=$(curl -fsSL "https://ghcr.io/token?service=ghcr.io&scope=repository:games-on-whales/base-app:pull" 2>/dev/null | jq -r '.token' || true)
    if [[ -n "$token" ]]; then
        manifest=$(curl -fsSL \
            -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
            -H "Authorization: Bearer $token" \
            "https://ghcr.io/v2/games-on-whales/base-app/manifests/${BASE_IMAGE_TAG}" 2>/dev/null || true)
        digest=$(echo "$manifest" | jq -r '.config.digest // empty' 2>/dev/null | sed 's/sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    # crane fallback
    if command -v crane &>/dev/null; then
        digest=$(crane digest "${BASE_IMAGE}:${BASE_IMAGE_TAG}" 2>/dev/null | sed 's/sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    # docker fallback
    if command -v docker &>/dev/null; then
        docker pull "${BASE_IMAGE}:${BASE_IMAGE_TAG}" >/dev/null 2>&1 || true
        digest=$(docker inspect --format='{{index .RepoDigests 0}}' "${BASE_IMAGE}:${BASE_IMAGE_TAG}" 2>/dev/null | \
            sed 's/.*@sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    echo "$digest"
}

get_current_drop_version() {
    grep '^DROP_APP_VERSION=' "$PINS_FILE" | cut -d'=' -f2 || echo ""
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

# Check base image
echo "Checking base image..."
current_base=$(get_current_base_digest) || abort "Could not read BASE_APP_IMAGE from $PINS_FILE"
latest_base=$(fetch_latest_base_digest)

if [[ -n "$latest_base" ]]; then
    if [[ "$current_base" != "$latest_base" ]]; then
        echo "Base image update available: ${current_base:0:12} -> ${latest_base:0:12}"
        updates+=("base")
        summary+="### Base Image\n\n| Field | Value |\n|-------|-------|\n| Previous | \`${current_base:0:16}...\` |\n| New | \`${latest_base:0:16}...\` |\n\n"
    else
        echo "Base image up to date"
    fi
else
    echo "Warning: Could not fetch latest base image digest"
fi

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
