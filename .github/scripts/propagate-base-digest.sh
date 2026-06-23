#!/usr/bin/env bash
# Propagate the currently published base:edge digest into dependent app pins.
#
# This is release-graph orchestration, not a dependency update for images/base.
# It runs from update.yml after ci.yml publishes a new base image and dispatches
# `base-digest-published`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

source "${REPO_ROOT}/images/base/update/lib/base-digest.sh"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

BASE_IMAGE="${REGISTRY_BASE_IMAGE:-ghcr.io/${GITHUB_REPOSITORY_OWNER:-baz00k}/gow-collection/base}"
BASE_IMAGE="${BASE_IMAGE,,}"

latest_digest=$(fetch_remote_digest "${BASE_IMAGE}:edge" || true)
if [[ -z "$latest_digest" ]]; then
    echo "::error::Could not resolve ${BASE_IMAGE}:edge"
    exit 1
fi

new_base_ref="${BASE_IMAGE}:edge@${latest_digest}"
changed=false
summary=""
repinned=()

for pins in "${REPO_ROOT}"/images/*/build/pins.env; do
    [[ "$pins" == "${REPO_ROOT}/images/base/build/pins.env" ]] && continue
    grep -q '^BASE_APP_IMAGE=' "$pins" || continue

    current=$(grep '^BASE_APP_IMAGE=' "$pins" | head -1 | cut -d= -f2-)
    if [[ "$current" == "$new_base_ref" ]]; then
        continue
    fi

    image_dir=$(dirname "$(dirname "$pins")")
    name=$(basename "$image_dir")
    echo "Repinning ${name}: ${current} -> ${new_base_ref}"
    inplace "s|^BASE_APP_IMAGE=.*|BASE_APP_IMAGE=${new_base_ref}|" "$pins"
    changed=true
    repinned+=("$name")
done

if [[ "$changed" == "true" ]]; then
    summary+="### Base Digest Propagation\n\n"
    summary+="Repinned dependent images to \`${latest_digest}\`:\n\n"
    for name in "${repinned[@]}"; do
        summary+="- ${name}\n"
    done
    summary+="\n"
fi

echo "applied=${changed}" >> "$GITHUB_OUTPUT"
{
    echo "summary_md<<EOF"
    printf "%b" "$summary"
    echo "EOF"
} >> "$GITHUB_OUTPUT"
