#!/usr/bin/env bash
# Check pins.env files produced by an update run before they reach a PR.
#
# Usage:
#   validate-pin-changes.sh <deps|base-digest> <repo-root> <candidate-dir>
#
# <candidate-dir> holds images/<name>/build/pins.env files written by update
# scripts that process upstream data, so they are untrusted. Each one must be
# the committed file with only values changed: same lines, same keys, same
# comments. Which keys may change, and what their values may look like, is
# decided here and never by the candidate:
#
#   deps          *_VERSION/*_TAG, *_SHA256, *_DIGEST, and *_URL (same host as
#                 the current pin; for github.com also the same owner/repo).
#                 Everything else (repos, BASE_IMAGE, BASE_APP_IMAGE) is fixed.
#   base-digest   only BASE_APP_IMAGE, and only to our base:edge@<digest>.
#
# On success the candidates are copied into <repo-root> and a markdown summary
# of the changes is printed to stdout. Any violation fails the whole run.

set -euo pipefail

LANE="${1:?lane required}"
ROOT="${2:?repo root required}"
CANDIDATES="${3:?candidate dir required}"
OWNER="${GITHUB_REPOSITORY_OWNER:?GITHUB_REPOSITORY_OWNER required}"
OWNER="${OWNER,,}"

fail() { echo "::error::$*" >&2; exit 1; }

[[ "$LANE" == "deps" || "$LANE" == "base-digest" ]] || fail "unknown lane '${LANE}'"

url_ok() {
    local old="$1" new="$2" re='^https://([a-z0-9.-]+)/([A-Za-z0-9._~%+/-]+)$'
    local old_host old_path new_host new_path

    [[ "$new" =~ $re ]] || return 1
    new_host="${BASH_REMATCH[1]}" new_path="${BASH_REMATCH[2]}"
    [[ "$old" =~ $re ]] || return 1
    old_host="${BASH_REMATCH[1]}" old_path="${BASH_REMATCH[2]}"

    # No traversal or encoded separators that could leave the repo path.
    [[ "/${new_path}/" != *"/../"* && "/${new_path}/" != *"/./"* && "$new_path" != *"//"* ]] || return 1
    [[ ! "$new_path" =~ %(2[fF]|5[cC]|2[eE]) ]] || return 1

    [[ "$new_host" == "$old_host" ]] || return 1
    if [[ "$new_host" == "github.com" ]]; then
        [[ "$(cut -d/ -f1-2 <<<"$new_path")" == "$(cut -d/ -f1-2 <<<"$old_path")" ]] || return 1
    fi
}

value_ok() {
    local key="$1" old="$2" new="$3"

    if [[ "$LANE" == "base-digest" ]]; then
        [[ "$key" == "BASE_APP_IMAGE" &&
           "$new" =~ ^ghcr\.io/${OWNER}/gow-collection/base:edge@sha256:[0-9a-f]{64}$ ]]
        return
    fi

    case "$key" in
        BASE_APP_IMAGE) return 1 ;;   # base-digest lane only
        *_SHA256) [[ "$new" =~ ^[0-9a-f]{64}$ ]] ;;
        *_DIGEST) [[ "$new" =~ ^sha256:[0-9a-f]{64}$ ]] ;;
        *_VERSION | *_TAG) [[ "$new" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ ]] ;;
        *_URL) url_ok "$old" "$new" ;;
        *) return 1 ;;
    esac
}

summary=""
validated=()

while IFS= read -r -d '' path; do
    rel="${path#"${CANDIDATES}"/}"
    [[ "$rel" =~ ^images/([a-z0-9][a-z0-9-]*)/build/pins\.env$ ]] || fail "unexpected file '${rel}'"
    name="${BASH_REMATCH[1]}"
    [[ -f "$path" && ! -L "$path" ]] || fail "${rel} is not a regular file"
    [[ -f "${ROOT}/${rel}" && ! -L "${ROOT}/${rel}" ]] || fail "${rel} does not exist in the repository"
    [[ $(stat -c %s "$path") -le 65536 ]] || fail "${rel} is too large"

    mapfile -t old_lines < "${ROOT}/${rel}"
    mapfile -t new_lines < "$path"
    [[ ${#old_lines[@]} -eq ${#new_lines[@]} ]] || fail "${rel}: lines were added or removed"

    rows=""
    for i in "${!old_lines[@]}"; do
        old_line="${old_lines[$i]}" new_line="${new_lines[$i]}"
        [[ "$old_line" == "$new_line" ]] && continue

        [[ "$old_line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || fail "${rel}:$((i + 1)): only KEY=VALUE lines may change"
        key="${BASH_REMATCH[1]}" old="${BASH_REMATCH[2]}"
        [[ "$new_line" == "${key}="* ]] || fail "${rel}:$((i + 1)): key ${key} was renamed"
        new="${new_line#"${key}="}"

        value_ok "$key" "$old" "$new" || fail "${rel}: ${LANE} updates may not set ${key}=${new}"
        rows+="| \`${key}\` | \`${old}\` | \`${new}\` |"$'\n'
    done

    [[ -n "$rows" ]] || continue
    validated+=("$rel")
    summary+="### ${name}"$'\n\n'"| Pin | Old | New |"$'\n'"| --- | --- | --- |"$'\n'"${rows}"$'\n'
done < <(find "$CANDIDATES" -mindepth 1 \( -type f -o -type l \) -print0 | sort -z)

# Directories and other entries are never expected.
if find "$CANDIDATES" -mindepth 1 ! -type d ! -type f ! -type l | grep -q .; then
    fail "unexpected entries in ${CANDIDATES}"
fi

[[ ${#validated[@]} -gt 0 ]] || fail "no pin changes to apply"

for rel in "${validated[@]}"; do
    cp -- "${CANDIDATES}/${rel}" "${ROOT}/${rel}"
done
printf '%s' "$summary"
