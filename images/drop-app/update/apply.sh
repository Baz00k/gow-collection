#!/usr/bin/env bash
# Apply drop-app dependency updates
# Updates: BASE_APP_IMAGE digest, Drop version and SHA256

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${SCRIPT_DIR}/../build/pins.env"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

BASE_IMAGE="${BASE_IMAGE:-ghcr.io/games-on-whales/base-app}"
BASE_IMAGE_TAG="${BASE_IMAGE_TAG:-edge}"
DROP_APP_REPO="${DROP_APP_REPO:-Drop-OSS/drop-app}"

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

get_current_drop_version() {
    grep '^DROP_APP_VERSION=' "$PINS_FILE" | cut -d'=' -f2 || echo ""
}

fetch_latest_drop_version() {
    local latest_raw
    latest_raw=$(curl -fsSL "https://api.github.com/repos/${DROP_APP_REPO}/releases/latest" | jq -r '.tag_name // empty')
    echo "${latest_raw#v}"
}

fetch_drop_sha256() {
    local version="$1"
    local deb_url="https://github.com/${DROP_APP_REPO}/releases/download/v${version}/Drop.Desktop.Client_${version}_amd64.deb"
    curl -fsSL -o /tmp/drop-desktop-client.deb "$deb_url"
    sha256sum /tmp/drop-desktop-client.deb | cut -d' ' -f1
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

current_drop=$(get_current_drop_version)
latest_drop=$(fetch_latest_drop_version)

if [[ -n "$latest_drop" && "$current_drop" != "$latest_drop" ]]; then
    echo "Updating drop-app: $current_drop -> $latest_drop"
    echo "Downloading drop-app v${latest_drop}..."
    drop_sha256=$(fetch_drop_sha256 "$latest_drop")
    echo "SHA256: $drop_sha256"
    
    inplace "s|^DROP_APP_VERSION=.*|DROP_APP_VERSION=${latest_drop}|" "$PINS_FILE"
    inplace "s|^DROP_APP_SHA256=.*|DROP_APP_SHA256=${drop_sha256}|" "$PINS_FILE"
    rm -f /tmp/drop-desktop-client.deb
    applied=true
    summary+="### Drop App\n\nUpdated from v${current_drop} to v${latest_drop}.\n\n"
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
