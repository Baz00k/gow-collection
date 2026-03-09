#!/usr/bin/env bash
# Apply steam dependency updates
# Updates: BASE_IMAGE digest, Decky Loader version/URL/SHA256, UMU Launcher version/URL/SHA256

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

fetch_latest_base_digest() {
    local digest=""

    local manifest
    manifest=$(curl -fsSL \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        "https://${BASE_IMAGE_REGISTRY}/v2/${BASE_IMAGE_NAME}/manifests/${BASE_IMAGE_TAG}" 2>/dev/null || true)
    if [[ -n "$manifest" ]]; then
        digest=$(echo "$manifest" | jq -r '.config.digest // empty' 2>/dev/null | sed 's/sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    if command -v crane &>/dev/null; then
        digest=$(crane digest "${BASE_IMAGE_REGISTRY}/${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}" 2>/dev/null | sed 's/sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    if command -v docker &>/dev/null; then
        docker pull "${BASE_IMAGE_REGISTRY}/${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}" >/dev/null 2>&1 || true
        digest=$(docker inspect --format='{{index .RepoDigests 0}}' "${BASE_IMAGE_REGISTRY}/${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}" 2>/dev/null | \
            sed 's/.*@sha256://' || true)
        [[ -n "$digest" ]] && { echo "$digest"; return 0; }
    fi

    echo "$digest"
}

get_current_base_digest() {
    local full_image
    full_image=$(grep '^BASE_IMAGE=' "$PINS_FILE" | cut -d'=' -f2) || return 1
    echo "$full_image" | sed 's/.*@sha256://'
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

fetch_file_sha256() {
    local url="$1"
    local output_file="$2"
    curl -fsSL "$url" -o "$output_file"
    sha256sum "$output_file" | cut -d' ' -f1
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

fetch_bwrap_commit() {
    local repo="$1"
    local version="$2"
    local tag_sha commit_sha

    # GitHub tags API: get the tag object, then dereference to commit
    if command -v gh &>/dev/null; then
        tag_sha=$(gh api "repos/${repo}/git/ref/tags/${version}" --jq '.object.sha' 2>/dev/null || echo "")
        if [[ -n "$tag_sha" ]]; then
            # Dereference annotated tag to commit
            commit_sha=$(gh api "repos/${repo}/git/tags/${tag_sha}" --jq '.object.sha' 2>/dev/null || echo "$tag_sha")
            echo "$commit_sha"
            return 0
        fi
    fi

    # Fallback: curl
    tag_sha=$(curl -fsSL "https://api.github.com/repos/${repo}/git/ref/tags/${version}" | jq -r '.object.sha // empty' 2>/dev/null || echo "")
    if [[ -n "$tag_sha" ]]; then
        commit_sha=$(curl -fsSL "https://api.github.com/repos/${repo}/git/tags/${tag_sha}" | jq -r '.object.sha // empty' 2>/dev/null || echo "$tag_sha")
        echo "$commit_sha"
        return 0
    fi

    echo ""
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

applied=false
summary=""

current_base=$(get_current_base_digest)
latest_base=$(fetch_latest_base_digest)

if [[ -n "$latest_base" && "$current_base" != "$latest_base" ]]; then
    echo "Updating base image: ${current_base:0:12} -> ${latest_base:0:12}"
    new_image="${BASE_IMAGE_REGISTRY}/${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}@sha256:${latest_base}"
    inplace "s|^BASE_IMAGE=.*|BASE_IMAGE=${new_image}|" "$PINS_FILE"
    applied=true
    summary+="### Base Image\n\nUpdated to \`${latest_base:0:16}...\`\n\n"
fi

decky_repo=$(get_decky_repo)
current_decky=$(get_current_decky_version)
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

umu_repo=$(get_umu_repo)
current_umu=$(get_current_umu_version)
latest_umu=$(fetch_latest_umu_version)

if [[ -n "$latest_umu" && "$current_umu" != "$latest_umu" ]]; then
    echo "Updating UMU Launcher: $current_umu -> $latest_umu"
    
    umu_url="https://github.com/${umu_repo}/releases/download/${latest_umu}/umu-launcher-${latest_umu}.fc43.rpm"
    
    echo "Downloading UMU Launcher RPM..."
    umu_sha=$(fetch_file_sha256 "$umu_url" /tmp/umu-launcher.rpm)
    echo "UMU Launcher SHA256: $umu_sha"
    
    inplace "s|^UMU_LAUNCHER_VERSION=.*|UMU_LAUNCHER_VERSION=${latest_umu}|" "$PINS_FILE"
    inplace "s|^UMU_LAUNCHER_URL=.*|UMU_LAUNCHER_URL=${umu_url}|" "$PINS_FILE"
    inplace "s|^UMU_LAUNCHER_SHA256=.*|UMU_LAUNCHER_SHA256=${umu_sha}|" "$PINS_FILE"
    
    rm -f /tmp/umu-launcher.rpm
    applied=true
    summary+="### UMU Launcher\n\nUpdated from v${current_umu} to v${latest_umu}.\n\n"
fi

bwrap_repo=$(get_bwrap_repo)
current_bwrap=$(get_current_bwrap_version)
latest_bwrap=$(fetch_latest_bwrap_version)

if [[ -n "$latest_bwrap" && "$current_bwrap" != "$latest_bwrap" ]]; then
    echo "Updating Bubblewrap: ${current_bwrap} -> ${latest_bwrap}"
    
    bwrap_commit=$(fetch_bwrap_commit "$bwrap_repo" "$latest_bwrap")
    if [[ -z "$bwrap_commit" ]]; then
        echo "Warning: Could not resolve commit for Bubblewrap ${latest_bwrap}, skipping"
    else
        echo "Bubblewrap commit: ${bwrap_commit}"
        inplace "s|^BUBBLEWRAP_VERSION=.*|BUBBLEWRAP_VERSION=${latest_bwrap}|" "$PINS_FILE"
        inplace "s|^BUBBLEWRAP_COMMIT=.*|BUBBLEWRAP_COMMIT=${bwrap_commit}|" "$PINS_FILE"
        applied=true
        summary+="### Bubblewrap\n\nUpdated from ${current_bwrap} to ${latest_bwrap} (commit: \`${bwrap_commit:0:12}\`).\n\n"
    fi
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
