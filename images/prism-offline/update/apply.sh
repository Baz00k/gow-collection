#!/usr/bin/env bash
# Apply prism-offline dependency updates
# Updates: BASE_APP_IMAGE digest, Prism version and AppImage SHA256s

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${SCRIPT_DIR}/../build/pins.env"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

BASE_IMAGE="${BASE_IMAGE:-ghcr.io/games-on-whales/base-app}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-edge}"
PRISM_REPO="${PRISM_REPO:-Diegiwg/PrismLauncher-Cracked}"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

abort() { echo "ERROR: $1" >&2; exit 1; }

fetch_latest_base_digest() {
    local digest=""

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

    if command -v crane &>/dev/null; then
        digest=$(crane digest "${BASE_IMAGE}:${BASE_IMAGE_TAG}" 2>/dev/null | sed 's/sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    if command -v docker &>/dev/null; then
        docker pull "${BASE_IMAGE}:${BASE_IMAGE_TAG}" >/dev/null 2>&1 || true
        digest=$(docker inspect --format='{{index .RepoDigests 0}}' "${BASE_IMAGE}:${BASE_IMAGE_TAG}" 2>/dev/null | \
            sed 's/.*@sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    echo "$digest"
}

get_current_base_digest() {
    local full_image
    full_image=$(grep '^BASE_APP_IMAGE=' "$PINS_FILE" | cut -d'=' -f2) || return 1
    echo "$full_image" | sed 's/.*@sha256://'
}

get_current_prism_version() {
    grep '^PRISM_LAUNCHER_VERSION=' "$PINS_FILE" | cut -d'=' -f2 || echo ""
}

fetch_latest_prism_version() {
    if command -v gh &>/dev/null; then
        gh api "repos/${PRISM_REPO}/releases/latest" --jq '.tag_name' | sed 's/^v//'
    else
        curl -fsSL "https://api.github.com/repos/${PRISM_REPO}/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//'
    fi
}

fetch_appimage_sha256() {
    local url="$1"
    local output_file="$2"
    curl -fsSL "$url" -o "$output_file"
    sha256sum "$output_file" | cut -d' ' -f1
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

applied=false
summary=""

current_base=$(get_current_base_digest)
latest_base=$(fetch_latest_base_digest)

if [[ -n "$latest_base" && "$current_base" != "$latest_base" ]]; then
    echo "Updating base image: ${current_base:0:12} -> ${latest_base:0:12}"
    new_image="${BASE_IMAGE}:${BASE_IMAGE_TAG}@sha256:${latest_base}"
    inplace "s|^BASE_APP_IMAGE=.*|BASE_APP_IMAGE=${new_image}|" "$PINS_FILE"
    applied=true
    summary+="### Base Image\n\nUpdated to \`${latest_base:0:16}...\`\n\n"
fi

current_prism=$(get_current_prism_version)
latest_prism=$(fetch_latest_prism_version)

if [[ -n "$latest_prism" && "$current_prism" != "$latest_prism" ]]; then
    echo "Updating Prism Launcher: $current_prism -> $latest_prism"
    
    base_url="https://github.com/${PRISM_REPO}/releases/download/${latest_prism}"
    x86_64_url="${base_url}/PrismLauncher-Linux-x86_64.AppImage"
    aarch64_url="${base_url}/PrismLauncher-Linux-aarch64.AppImage"
    
    echo "Downloading x86_64 AppImage..."
    x86_64_sha=$(fetch_appimage_sha256 "$x86_64_url" /tmp/PrismLauncher-x86_64.AppImage)
    echo "x86_64 SHA256: $x86_64_sha"
    
    echo "Downloading aarch64 AppImage..."
    aarch64_sha=$(fetch_appimage_sha256 "$aarch64_url" /tmp/PrismLauncher-aarch64.AppImage)
    echo "aarch64 SHA256: $aarch64_sha"
    
    inplace "s|^PRISM_LAUNCHER_VERSION=.*|PRISM_LAUNCHER_VERSION=${latest_prism}|" "$PINS_FILE"
    inplace "s|^PRISM_LAUNCHER_APPIMAGE_X86_64_URL=.*|PRISM_LAUNCHER_APPIMAGE_X86_64_URL=${x86_64_url}|" "$PINS_FILE"
    inplace "s|^PRISM_LAUNCHER_APPIMAGE_X86_64_SHA256=.*|PRISM_LAUNCHER_APPIMAGE_X86_64_SHA256=${x86_64_sha}|" "$PINS_FILE"
    inplace "s|^PRISM_LAUNCHER_APPIMAGE_AARCH64_URL=.*|PRISM_LAUNCHER_APPIMAGE_AARCH64_URL=${aarch64_url}|" "$PINS_FILE"
    inplace "s|^PRISM_LAUNCHER_APPIMAGE_AARCH64_SHA256=.*|PRISM_LAUNCHER_APPIMAGE_AARCH64_SHA256=${aarch64_sha}|" "$PINS_FILE"
    
    rm -f /tmp/PrismLauncher-x86_64.AppImage /tmp/PrismLauncher-aarch64.AppImage
    applied=true
    summary+="### Prism Launcher\n\nUpdated from v${current_prism} to v${latest_prism}.\n\n"
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
