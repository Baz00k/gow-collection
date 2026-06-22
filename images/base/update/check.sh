#!/usr/bin/env bash
# Check for base image dependency updates
# Checks: Fedora base digest (rolling tag -> digest), Bubblewrap version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

# Resolve the digest that a registry tag currently points at.
# Works against the Fedora registry (no auth) and is the same approach the app
# images use against GHCR.
fetch_remote_digest() {
    local ref="$1"            # registry/repo:tag
    local registry repo tag rest
    rest="${ref#*/}"          # repo[/...]:tag  (strip registry host)
    registry="${ref%%/*}"
    repo="${rest%:*}"
    tag="${rest##*:}"

    # crane (most reliable, handles auth + multi-arch indexes)
    if command -v crane &>/dev/null; then
        crane digest "$ref" 2>/dev/null && return 0
    fi

    # skopeo fallback
    if command -v skopeo &>/dev/null; then
        skopeo inspect --raw "docker://${ref}" 2>/dev/null \
            | { command -v sha256sum >/dev/null && { local body; body=$(cat); printf 'sha256:%s' "$(printf '%s' "$body" | sha256sum | cut -d' ' -f1)"; }; } \
            && return 0
    fi

    # Registry v2 API fallback (Fedora registry is anonymous-pull).
    # Read the Docker-Content-Digest response header for the manifest.
    local accept digest
    accept="application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json"
    digest=$(curl -fsSL -I \
        -H "Accept: ${accept}" \
        "https://${registry}/v2/${repo}/manifests/${tag}" 2>/dev/null \
        | tr -d '\r' \
        | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}' \
        | tail -1)
    [[ -n "$digest" ]] && { echo "$digest"; return 0; }

    return 1
}

get_bwrap_repo() {
    local repo
    repo=$(get_pin BUBBLEWRAP_REPO)
    echo "${repo:-containers/bubblewrap}"
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

# --- Fedora base digest ---
echo "Checking Fedora base image digest..."
base_image=$(get_pin BASE_IMAGE)
current_digest=$(get_pin BASE_IMAGE_DIGEST)
[[ -z "$base_image" ]] && abort "BASE_IMAGE not set in $PINS_FILE"

latest_digest=$(fetch_remote_digest "$base_image" || true)

if [[ -n "$latest_digest" ]]; then
    if [[ "$current_digest" != "$latest_digest" ]]; then
        echo "Base image update available: ${current_digest:-none} -> ${latest_digest}"
        updates+=("base")
        summary+="### Fedora Base\n\n| Field | Value |\n|-------|-------|\n| Tag | \`${base_image}\` |\n| Previous | \`${current_digest:-none}\` |\n| New | \`${latest_digest}\` |\n\n"
    else
        echo "Base image up to date"
    fi
else
    echo "Warning: Could not resolve latest digest for ${base_image}"
fi

# --- Bubblewrap ---
echo "Checking Bubblewrap..."
current_bwrap=$(get_pin BUBBLEWRAP_VERSION)
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
