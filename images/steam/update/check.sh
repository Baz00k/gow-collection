#!/usr/bin/env bash
# Check for steam dependency updates
# Checks: shared base image digest (GHCR), Decky Loader version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

# Shared base image (defaults derived from the BASE_APP_IMAGE pin).
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/baz00k/gow-collection/base}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-edge}"

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

get_current_base_digest() {
    local full_image
    full_image=$(get_pin BASE_APP_IMAGE)
    [[ -z "$full_image" ]] && return 1
    echo "$full_image" | sed 's/.*@//'
}

fetch_latest_base_digest() {
    # GHCR repo path without the registry host, e.g. baz00k/gow-collection/base
    local repo="${BASE_IMAGE#ghcr.io/}"
    local token manifest digest

    token=$(curl -fsSL "https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull" 2>/dev/null | jq -r '.token' || true)
    if [[ -n "$token" && "$token" != "null" ]]; then
        digest=$(curl -fsSL -I \
            -H "Accept: application/vnd.oci.image.index.v1+json" \
            -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
            -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
            -H "Authorization: Bearer ${token}" \
            "https://ghcr.io/v2/${repo}/manifests/${BASE_IMAGE_TAG}" 2>/dev/null \
            | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}' | tail -1)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    if command -v crane &>/dev/null; then
        crane digest "${BASE_IMAGE}:${BASE_IMAGE_TAG}" 2>/dev/null && return 0
    fi

    return 1
}

get_decky_repo() {
    local repo
    repo=$(get_pin DECKY_LOADER_REPO)
    echo "${repo:-SteamDeckHomebrew/decky-loader}"
}

fetch_latest_decky_version() {
    local repo
    repo=$(get_decky_repo)
    if command -v gh &>/dev/null; then
        gh api "repos/${repo}/releases/latest" --jq '.tag_name' | sed 's/^v//'
    else
        curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//'
    fi
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

updates=()
summary=""

# --- Base image digest ---
echo "Checking base image..."
current_base=$(get_current_base_digest) || abort "Could not read BASE_APP_IMAGE from $PINS_FILE"
latest_base=$(fetch_latest_base_digest || true)

if [[ -n "$latest_base" ]]; then
    if [[ "$current_base" != "$latest_base" ]]; then
        echo "Base image update available: ${current_base} -> ${latest_base}"
        updates+=("base")
        summary+="### Base Image\n\nUpdated to \`${latest_base}\`.\n\n"
    else
        echo "Base image up to date"
    fi
else
    echo "Warning: Could not fetch latest base image digest"
fi

# --- Decky Loader ---
echo "Checking Decky Loader..."
current_decky=$(get_pin DECKY_LOADER_VERSION)
latest_decky=$(fetch_latest_decky_version)

if [[ -n "$latest_decky" ]]; then
    if [[ "$current_decky" != "$latest_decky" ]]; then
        echo "Decky Loader update available: $current_decky -> $latest_decky"
        updates+=("decky")
        summary+="### Decky Loader\n\nUpdated from v${current_decky} to v${latest_decky}.\n\n"
    else
        echo "Decky Loader up to date"
    fi
else
    echo "Warning: Could not fetch latest Decky Loader version"
fi

if [[ ${#updates[@]} -gt 0 ]]; then
    echo "update_available=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "update_available=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
