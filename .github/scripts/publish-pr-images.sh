#!/usr/bin/env bash
# Push the images a PR's CI run built to GHCR under PR-scoped tags.
#
# Usage:
#   publish-pr-images.sh <artifact-dir>
#
# Inputs (env):
#   PR_NUMBER      pull request number
#   HEAD_SHA       PR head commit the CI run built
#   IMAGE_PREFIX   registry path, e.g. ghcr.io/<owner>/gow-collection
#   SUMMARY_FILE   markdown table rows are appended here (default /dev/null)
#
# The archives come from a PR build that ran unreviewed code, so this only
# loads and retags them: nothing inside is run, and the only thing taken from an
# archive is an image name that must match `gow-ci/<name>:<sha>`. Destinations
# are always `pr-<n>` tags, never `edge` or `sha-*`.

set -euo pipefail

ARTIFACT_DIR="${1:?artifact dir required}"
SUMMARY_FILE="${SUMMARY_FILE:-/dev/null}"

[[ "${PR_NUMBER:-}" =~ ^[0-9]+$ ]] || { echo "::error::Invalid PR_NUMBER '${PR_NUMBER:-}'"; exit 1; }
[[ "${HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::Invalid HEAD_SHA '${HEAD_SHA:-}'"; exit 1; }
[[ -n "${IMAGE_PREFIX:-}" ]] || { echo "::error::IMAGE_PREFIX required"; exit 1; }
IMAGE_PREFIX="${IMAGE_PREFIX,,}"   # GHCR repos are lowercase

loaded=()
while IFS= read -r -d '' archive; do
    case "$archive" in
        *.tar.zst) out=$(zstd -dc "$archive" | docker load) ;;
        *.tar) out=$(docker load --input "$archive") ;;
        *) continue ;;
    esac
    mapfile -t -O "${#loaded[@]}" loaded < <(sed -n 's/^Loaded image: //p' <<<"$out")
done < <(find "$ARTIFACT_DIR" -type f -print0 | sort -z)

if [[ ${#loaded[@]} -eq 0 ]]; then
    echo "::error::No images found in ${ARTIFACT_DIR}"
    exit 1
fi

for ref in "${loaded[@]}"; do
    if [[ ! "$ref" =~ ^gow-ci/([a-z0-9][a-z0-9-]*):[0-9a-f]{40}$ ]]; then
        echo "::error::Unexpected image '${ref}' in PR artifacts"
        exit 1
    fi
    name="${BASH_REMATCH[1]}"
    dest="${IMAGE_PREFIX}/${name}"

    # Immutable per-commit tag first, then move the PR tag testers pull.
    for tag in "pr-${PR_NUMBER}-${HEAD_SHA:0:7}" "pr-${PR_NUMBER}"; do
        docker tag "$ref" "${dest}:${tag}"
        docker push "${dest}:${tag}"
    done

    digest=$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' "${dest}:pr-${PR_NUMBER}" \
        | sed -n "s|^${dest}@||p" | head -1)
    # shellcheck disable=SC2016  # backticks are markdown, not expansions
    printf '| %s | `%s:pr-%s` | `%s` |\n' "$name" "$dest" "$PR_NUMBER" "$digest" >> "$SUMMARY_FILE"
    echo "::notice::Published ${dest}:pr-${PR_NUMBER}@${digest}"
done
