#!/usr/bin/env bash
# Apply drop-app dependency updates
# Updates: Drop release tag, client version, RPM URL and SHA256

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
PIN_UPDATES="${PIN_UPDATES:-/dev/stdout}"

DROP_APP_REPO="${DROP_APP_REPO:-Drop-OSS/drop}"

abort() { echo "ERROR: $1" >&2; exit 1; }

# Report a new value; update.yml writes it to pins.env once this script succeeds.
pin() { printf '%s=%s\n' "$1" "$2" >> "$PIN_UPDATES"; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

get_current_drop_tag() {
    local tag
    tag=$(get_pin DROP_APP_TAG)
    echo "${tag:-v$(get_pin DROP_APP_VERSION)}"
}

fetch_latest_drop_tag() {
    curl -fsSL "https://api.github.com/repos/${DROP_APP_REPO}/releases/latest" | jq -r '.tag_name // empty'
}

fetch_release_json() {
    local repo="$1" tag="$2"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/tags/${tag}"
}

asset_name() {
    local release_json="$1" pattern="$2"
    jq -r --arg pattern "$pattern" '.assets[].name | select(test($pattern))' <<< "$release_json" | head -1
}

asset_digest() {
    local release_json="$1" asset="$2"
    jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | .digest // empty' <<< "$release_json" \
        | sed 's/^sha256://'
}

# Release digests are usually present, but fall back to hashing the download so
# an older release without them still works. A failed download or an empty hash
# must never reach pins.env, the caller runs under a command substitution where
# errexit is not inherited.
resolve_digest() {
    local release_json="$1" asset="$2" url="$3" digest tmp

    digest=$(asset_digest "$release_json" "$asset")
    if [[ -z "$digest" ]]; then
        echo "Release digest missing; downloading ${asset} to calculate SHA256..." >&2
        tmp=$(mktemp)
        if ! curl -fsSL "$url" -o "$tmp"; then
            rm -f "$tmp"
            abort "failed to download ${url}"
        fi
        digest=$(sha256sum "$tmp" | cut -d' ' -f1)
        rm -f "$tmp"
    fi

    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || abort "invalid SHA256 for ${asset}: '${digest}'"
    echo "$digest"
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

# Phase 1: work out and validate every update before reporting any, so a
# failure part-way through reports nothing.

drop_tag=""
drop_version=""
drop_url=""
drop_sha256=""

current_drop=$(get_current_drop_tag)
latest_drop=$(fetch_latest_drop_tag)

if [[ -n "$latest_drop" && "$current_drop" != "$latest_drop" ]]; then
    echo "Resolving drop-app ${current_drop} -> ${latest_drop}"
    release_json=$(fetch_release_json "$DROP_APP_REPO" "$latest_drop")

    rpm_asset=$(asset_name "$release_json" '^Drop\.Desktop\.Client-.*-1\.x86_64\.rpm$')
    [[ -z "$rpm_asset" ]] && abort "no x86_64 RPM asset in release ${latest_drop}"

    # Release tags may carry a pre-release suffix (v0.4.0-rc-6) while the asset
    # filename uses the bare client version (Drop.Desktop.Client-0.4.0-1...).
    drop_version=$(sed -E 's/^Drop\.Desktop\.Client-(.+)-1\.x86_64\.rpm$/\1/' <<< "$rpm_asset")
    drop_tag="$latest_drop"
    drop_url="https://github.com/${DROP_APP_REPO}/releases/download/${latest_drop}/${rpm_asset}"
    drop_sha256=$(resolve_digest "$release_json" "$rpm_asset" "$drop_url")
    echo "Drop client version ${drop_version}, SHA256 ${drop_sha256}"
fi

# Phase 2: report the validated updates.
if [[ -n "$drop_tag" ]]; then
    pin DROP_APP_VERSION "$drop_version"
    pin DROP_APP_TAG "$drop_tag"
    pin DROP_APP_RPM_X86_64_URL "$drop_url"
    pin DROP_APP_RPM_X86_64_SHA256 "$drop_sha256"
fi
