#!/usr/bin/env bash
# Apply steam dependency updates
# Updates: shared base image digest (GHCR), Decky Loader version/URL/SHA256

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

BASE_IMAGE="${BASE_IMAGE:-ghcr.io/baz00k/gow-collection/base}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-edge}"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

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
    local repo="${BASE_IMAGE#ghcr.io/}"
    local token digest

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

fetch_file_sha256() {
    local url="$1" output_file="$2"
    curl -fsSL "$url" -o "$output_file"
    sha256sum "$output_file" | cut -d' ' -f1
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

applied=false
summary=""

# --- Base image digest ---
current_base=$(get_current_base_digest || true)
latest_base=$(fetch_latest_base_digest || true)

if [[ -n "$latest_base" && "$current_base" != "$latest_base" ]]; then
    echo "Updating base image: ${current_base} -> ${latest_base}"
    new_image="${BASE_IMAGE}:${BASE_IMAGE_TAG}@${latest_base}"
    inplace "s|^BASE_APP_IMAGE=.*|BASE_APP_IMAGE=${new_image}|" "$PINS_FILE"
    applied=true
    summary+="### Base Image\n\nUpdated to \`${latest_base}\`.\n\n"
fi

# --- Decky Loader ---
decky_repo=$(get_decky_repo)
current_decky=$(get_pin DECKY_LOADER_VERSION)
latest_decky=$(fetch_latest_decky_version)

if [[ -n "$latest_decky" && "$current_decky" != "$latest_decky" ]]; then
    echo "Updating Decky Loader: $current_decky -> $latest_decky"
    decky_url="https://github.com/${decky_repo}/releases/download/v${latest_decky}/PluginLoader"
    echo "Downloading PluginLoader..."
    decky_sha=$(fetch_file_sha256 "$decky_url" /tmp/PluginLoader)
    echo "PluginLoader SHA256: $decky_sha"

    inplace "s|^DECKY_LOADER_VERSION=.*|DECKY_LOADER_VERSION=${latest_decky}|" "$PINS_FILE"
    inplace "s|^DECKY_LOADER_URL=.*|DECKY_LOADER_URL=${decky_url}|" "$PINS_FILE"
    inplace "s|^DECKY_LOADER_SHA256=.*|DECKY_LOADER_SHA256=${decky_sha}|" "$PINS_FILE"

    rm -f /tmp/PluginLoader
    applied=true
    summary+="### Decky Loader\n\nUpdated from v${current_decky} to v${latest_decky}.\n\n"
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
