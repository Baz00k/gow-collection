#!/usr/bin/env bash
# Apply base image dependency updates.
# Updates: Fedora base digest (BASE_IMAGE_DIGEST), Bubblewrap version/commit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

source "${SCRIPT_DIR}/lib/base-digest.sh"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
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

fetch_bwrap_commit() {
    local repo="$1"
    local version="$2"
    local tag_sha commit_sha

    if command -v gh &>/dev/null; then
        tag_sha=$(gh api "repos/${repo}/git/ref/tags/${version}" --jq '.object.sha' 2>/dev/null || echo "")
        if [[ -n "$tag_sha" ]]; then
            commit_sha=$(gh api "repos/${repo}/git/tags/${tag_sha}" --jq '.object.sha' 2>/dev/null || echo "$tag_sha")
            echo "$commit_sha"
            return 0
        fi
    fi

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

# --- Fedora base digest ---
base_image=$(get_pin BASE_IMAGE)
current_digest=$(get_pin BASE_IMAGE_DIGEST)
latest_digest=$(fetch_remote_digest "$base_image" || true)

if [[ -n "$latest_digest" && "$current_digest" != "$latest_digest" ]]; then
    echo "Updating Fedora base digest: ${current_digest:-none} -> ${latest_digest}"
    inplace "s|^BASE_IMAGE_DIGEST=.*|BASE_IMAGE_DIGEST=${latest_digest}|" "$PINS_FILE"
    applied=true
    summary+="### Fedora Base\n\nUpdated digest to \`${latest_digest}\`.\n\n"
fi

# --- Bubblewrap ---
bwrap_repo=$(get_bwrap_repo)
current_bwrap=$(get_pin BUBBLEWRAP_VERSION)
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
