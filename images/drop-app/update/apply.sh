#!/usr/bin/env bash
# Apply drop-app dependency updates
# Updates: Drop release tag, client version, RPM URL and SHA256

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

DROP_APP_REPO="${DROP_APP_REPO:-Drop-OSS/drop}"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

set_pin() {
    local key="$1" value="$2" after="${3:-}"
    if grep -q "^${key}=" "$PINS_FILE"; then
        inplace "s|^${key}=.*|${key}=${value}|" "$PINS_FILE"
    elif [[ -n "$after" ]] && grep -q "^${after}=" "$PINS_FILE"; then
        inplace "/^${after}=/a ${key}=${value}" "$PINS_FILE"
    else
        printf '%s=%s\n' "${key}" "${value}" >> "$PINS_FILE"
    fi
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
    local tag="$1"
    curl -fsSL "https://api.github.com/repos/${DROP_APP_REPO}/releases/tags/${tag}"
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

fetch_file_sha256() {
    local url="$1" output_file="$2"
    curl -fsSL "$url" -o "$output_file"
    sha256sum "$output_file" | cut -d' ' -f1
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

applied=false
summary=""

current_drop=$(get_current_drop_tag)
latest_drop=$(fetch_latest_drop_tag)

if [[ -n "$latest_drop" && "$current_drop" != "$latest_drop" ]]; then
    echo "Updating drop-app: ${current_drop} -> ${latest_drop}"
    release_json=$(fetch_release_json "$latest_drop")

    rpm_asset=$(asset_name "$release_json" '^Drop\.Desktop\.Client-.*-1\.x86_64\.rpm$')
    [[ -z "$rpm_asset" ]] && abort "no x86_64 RPM asset in release ${latest_drop}"

    # Release tags may carry a pre-release suffix (v0.4.0-rc-6) while the asset
    # filename uses the bare client version (Drop.Desktop.Client-0.4.0-1...).
    client_version=$(sed -E 's/^Drop\.Desktop\.Client-(.+)-1\.x86_64\.rpm$/\1/' <<< "$rpm_asset")
    rpm_url="https://github.com/${DROP_APP_REPO}/releases/download/${latest_drop}/${rpm_asset}"

    rpm_sha256=$(asset_digest "$release_json" "$rpm_asset")
    if [[ -z "$rpm_sha256" ]]; then
        echo "Release digest missing; downloading ${rpm_asset} to calculate SHA256..."
        rpm_sha256=$(fetch_file_sha256 "$rpm_url" /tmp/drop-desktop-client.rpm)
    fi
    echo "Client version: ${client_version}"
    echo "RPM SHA256: ${rpm_sha256}"

    set_pin DROP_APP_VERSION "$client_version"
    set_pin DROP_APP_TAG "$latest_drop" DROP_APP_VERSION
    set_pin DROP_APP_RPM_X86_64_URL "$rpm_url"
    set_pin DROP_APP_RPM_X86_64_SHA256 "$rpm_sha256"
    rm -f /tmp/drop-desktop-client.rpm
    applied=true
    summary+="### Drop App\n\nUpdated from ${current_drop} to ${latest_drop} (client ${client_version}).\n\n"
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
