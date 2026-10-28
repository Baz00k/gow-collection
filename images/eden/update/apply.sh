#!/usr/bin/env bash
# Apply Eden updates: version, AppImage URL, and AppImage SHA256.
#
# Upstream publishes no checksum files, so the SHA256 is taken from the
# downloaded artifact. Pins are only rewritten after a successful download, and
# the asset URL is read from the release API rather than built from a template
# so mirror or filename changes fail loudly instead of pinning nothing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

EDEN_API_URL="${EDEN_API_URL:-https://git.eden-emu.dev/api/v1/repos/eden-emu/eden/releases?limit=30}"
STABLE_TAG_REGEX='^v?[0-9]+\.[0-9]+\.[0-9]+$'
# amd64 + PGO: upstream's recommended generic Linux artifact. Switch to
# "legacy-clang-pgo" for pre-Haswell/pre-Ryzen CPUs.
EDEN_LINUX_VARIANT="${EDEN_LINUX_VARIANT:-amd64-clang-pgo}"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

fetch_releases() {
    curl -fsSL "$EDEN_API_URL" || abort "could not fetch ${EDEN_API_URL}"
}

select_stable_tag() {
    local releases_json="$1"

    printf '%s' "$releases_json" | jq -r --arg re "$STABLE_TAG_REGEX" '
        [ .[]
          | select((.draft // false) | not)
          | select((.prerelease // false) | not)
          | select(.tag_name | test($re))
        ] | first | .tag_name // empty'
}

fetch_asset_url() {
    local releases_json="$1"
    local tag="$2"
    local suffix="-${EDEN_LINUX_VARIANT}.AppImage"
    local url

    url=$(printf '%s' "$releases_json" | jq -r --arg tag "$tag" --arg suffix "$suffix" '
        [ .[]
          | select(.tag_name == $tag)
          | .assets[]?
          | select(.name | endswith($suffix))
        ] | first | .browser_download_url // empty')

    if [[ -z "$url" ]]; then
        # Fallback for releases whose assets are not exposed through the API.
        url="https://stable.eden-emu.dev/${tag}/Eden-Linux-${tag}${suffix}"
    fi

    printf '%s' "$url"
}

fetch_appimage_sha256() {
    local url="$1"
    local output_file="$2"

    rm -f "$output_file"
    if ! curl -fsSL "$url" -o "$output_file"; then
        return 1
    fi
    if [[ ! -s "$output_file" ]]; then
        return 1
    fi

    sha256sum "$output_file" | cut -d' ' -f1
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

applied=false
summary=""

current_eden=$(get_pin EDEN_VERSION)
releases_json=$(fetch_releases)
latest_tag=$(select_stable_tag "$releases_json")
[[ -n "$latest_tag" ]] || abort "could not determine latest stable Eden release"
latest_eden="${latest_tag#v}"

if [[ "$current_eden" != "$latest_eden" ]]; then
    echo "Updating Eden: $current_eden -> $latest_eden"

    appimage_url=$(fetch_asset_url "$releases_json" "$latest_tag")
    [[ -n "$appimage_url" ]] || abort "no Linux ${EDEN_LINUX_VARIANT} asset for ${latest_tag}"

    echo "Downloading ${appimage_url}"
    tmp_appimage="$(mktemp "${TMPDIR:-/tmp}/eden-appimage.XXXXXX")"
    trap 'rm -f "${tmp_appimage:-}"' EXIT

    if ! appimage_sha=$(fetch_appimage_sha256 "$appimage_url" "$tmp_appimage"); then
        abort "failed to download ${appimage_url}"
    fi
    [[ -n "$appimage_sha" ]] || abort "downloaded artifact produced no checksum"
    echo "SHA256: $appimage_sha"

    inplace "s|^EDEN_VERSION=.*|EDEN_VERSION=${latest_eden}|" "$PINS_FILE"
    inplace "s|^EDEN_APPIMAGE_URL=.*|EDEN_APPIMAGE_URL=${appimage_url}|" "$PINS_FILE"
    inplace "s|^EDEN_APPIMAGE_SHA256=.*|EDEN_APPIMAGE_SHA256=${appimage_sha}|" "$PINS_FILE"

    applied=true
    summary+="### Eden\n\nUpdated from v${current_eden} to v${latest_eden}.\n\n"
else
    echo "Eden already at v${current_eden}"
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
