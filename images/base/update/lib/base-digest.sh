#!/usr/bin/env bash
# Shared helper: resolve the current digest of a registry tag.
#
# This is the single source of truth for "what digest does this tag point at".
# It is used by base-rebuild.yml to propagate the freshly published base image
# digest into every dependent image's pins.env, and by images/base/update to
# track the upstream Fedora rolling tag. No other copy of this logic should
# exist in the repository.
#
# Usage:
#   source images/base/update/lib/base-digest.sh
#   digest=$(fetch_remote_digest "ghcr.io/<owner>/gow-collection/base:edge")
#
# Returns the digest (sha256:...) on stdout and exit 0, or exit 1 if it could
# not be resolved. Works against anonymous-pull registries (Fedora) and GHCR
# (which requires a pull token for anonymous access).

# Resolve the digest a registry reference currently points at.
#   $1 = registry/repo:tag  (e.g. ghcr.io/owner/gow-collection/base:edge)
fetch_remote_digest() {
    local ref="$1"
    local registry repo tag rest

    rest="${ref#*/}"          # strip registry host -> repo[/...]:tag
    registry="${ref%%/*}"
    repo="${rest%:*}"
    tag="${rest##*:}"

    # crane is the most reliable (handles auth + multi-arch indexes).
    if command -v crane &>/dev/null; then
        crane digest "$ref" 2>/dev/null && return 0
    fi

    # Registry v2 API fallback. GHCR needs an anonymous pull token; the Fedora
    # registry ignores the Authorization header, so requesting a token is safe
    # for both.
    local accept token auth_header digest
    accept="application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json"

    auth_header=()
    if command -v jq &>/dev/null; then
        token=$(curl -fsSL "https://${registry}/token?service=${registry}&scope=repository:${repo}:pull" 2>/dev/null \
            | jq -r '.token // empty' 2>/dev/null || true)
        [[ -n "$token" ]] && auth_header=(-H "Authorization: Bearer ${token}")
    fi

    digest=$(curl -fsSL -I \
        -H "Accept: ${accept}" \
        "${auth_header[@]}" \
        "https://${registry}/v2/${repo}/manifests/${tag}" 2>/dev/null \
        | tr -d '\r' \
        | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}' \
        | tail -1)
    [[ -n "$digest" ]] && { echo "$digest"; return 0; }

    return 1
}
