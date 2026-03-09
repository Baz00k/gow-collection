#!/usr/bin/env bash
# Check for steam dependency updates
# Checks: BASE_IMAGE digest, Decky Loader version, UMU Launcher version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${SCRIPT_DIR}/../build/pins.env"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

BASE_IMAGE_REGISTRY="${BASE_IMAGE_REGISTRY:-registry.fedoraproject.org}"
BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-fedora}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-43}"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

abort() { echo "ERROR: $1" >&2; exit 1; }

get_current_base_digest() {
    local full_image
    full_image=$(grep '^BASE_IMAGE=' "$PINS_FILE" | cut -d'=' -f2) || return 1
    [[ -z "$full_image" ]] && return 1
    echo "$full_image" | sed 's/.*@sha256://'
}

fetch_latest_base_digest() {
    local digest=""

    # Try Docker Registry HTTP API V2 for Fedora
    local manifest
    manifest=$(curl -fsSL \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        "https://${BASE_IMAGE_REGISTRY}/v2/${BASE_IMAGE_NAME}/manifests/${BASE_IMAGE_TAG}" 2>/dev/null || true)
    if [[ -n "$manifest" ]]; then
        digest=$(echo "$manifest" | jq -r '.config.digest // empty' 2>/dev/null | sed 's/sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    # Try crane
    if command -v crane &>/dev/null; then
        digest=$(crane digest "${BASE_IMAGE_REGISTRY}/${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}" 2>/dev/null | sed 's/sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    # Try docker
    if command -v docker &>/dev/null; then
        docker pull "${BASE_IMAGE_REGISTRY}/${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}" >/dev/null 2>&1 || true
        digest=$(docker inspect --format='{{index .RepoDigests 0}}' "${BASE_IMAGE_REGISTRY}/${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}" 2>/dev/null | \
            sed 's/.*@sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    echo "$digest"
}

get_current_decky_version() {
    grep '^DECKY_LOADER_VERSION=' "$PINS_FILE" | cut -d'=' -f2 || echo ""
}

get_decky_repo() {
    grep '^DECKY_LOADER_REPO=' "$PINS_FILE" | cut -d'=' -f2 || echo "SteamDeckHomebrew/decky-loader"
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

get_current_umu_version() {
    grep '^UMU_LAUNCHER_VERSION=' "$PINS_FILE" | cut -d'=' -f2 || echo ""
}

get_umu_repo() {
    grep '^UMU_LAUNCHER_REPO=' "$PINS_FILE" | cut -d'=' -f2 || echo "Open-Wine-Components/umu-launcher"
}

fetch_latest_umu_version() {
    local repo
    repo=$(get_umu_repo)
    if command -v gh &>/dev/null; then
        gh api "repos/${repo}/releases/latest" --jq '.tag_name' | sed 's/^v//'
    else
        curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//'
    fi
}

get_current_bwrap_version() {
    grep '^BUBBLEWRAP_VERSION=' "$PINS_FILE" | cut -d'=' -f2 || echo ""
}

get_bwrap_repo() {
    grep '^BUBBLEWRAP_REPO=' "$PINS_FILE" | cut -d'=' -f2 || echo "containers/bubblewrap"
}

fetch_latest_bwrap_version() {
    local repo
    repo=$(get_bwrap_repo)
    if command -v gh &>/dev/null; then
        gh api "repos/${repo}/releases/latest" --jq '.tag_name'
    else
        curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty'
    fi
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

updates=()
summary=""

echo "Checking base image..."
current_base=$(get_current_base_digest) || abort "Could not read BASE_IMAGE from $PINS_FILE"
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

echo "Checking Decky Loader..."
current_decky=$(get_current_decky_version)
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

echo "Checking UMU Launcher..."
current_umu=$(get_current_umu_version)
latest_umu=$(fetch_latest_umu_version)

if [[ -n "$latest_umu" ]]; then
    if [[ "$current_umu" != "$latest_umu" ]]; then
        echo "UMU Launcher update available: $current_umu -> $latest_umu"
        updates+=("umu")
        summary+="### UMU Launcher\n\nUpdated from v${current_umu} to v${latest_umu}.\n\n"
    else
        echo "UMU Launcher up to date"
    fi
else
    echo "Warning: Could not fetch latest UMU Launcher version"
fi

echo "Checking Bubblewrap..."
current_bwrap=$(get_current_bwrap_version)
latest_bwrap=$(fetch_latest_bwrap_version)

if [[ -n "$latest_bwrap" ]]; then
    if [[ "$current_bwrap" != "$latest_bwrap" ]]; then
        echo "Bubblewrap update available: ${current_bwrap} -> ${latest_bwrap}"
        updates+=("bwrap")
        summary+="### Bubblewrap\n\nUpdated from ${current_bwrap} to ${latest_bwrap}.\n\n"
    else
        echo "Bubblewrap up to date"
    fi
else
    echo "Warning: Could not fetch latest Bubblewrap version"
fi

if [[ ${#updates[@]} -gt 0 ]]; then
    echo "update_available=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "update_available=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
