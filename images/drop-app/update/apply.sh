#!/usr/bin/env bash
# Apply drop-app dependency updates
# Updates: Drop version and RPM SHA256

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

DROP_APP_REPO="${DROP_APP_REPO:-Drop-OSS/drop-app}"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

get_current_drop_version() {
    get_pin DROP_APP_VERSION
}

fetch_latest_drop_version() {
    local latest_raw
    latest_raw=$(curl -fsSL "https://api.github.com/repos/${DROP_APP_REPO}/releases/latest" | jq -r '.tag_name // empty')
    echo "${latest_raw#v}"
}

fetch_file_sha256() {
    local url="$1" output_file="$2"
    curl -fsSL "$url" -o "$output_file"
    sha256sum "$output_file" | cut -d' ' -f1
}

fetch_drop_release_digest() {
    local version="$1"
    local asset="$2"

    curl -fsSL "https://api.github.com/repos/${DROP_APP_REPO}/releases/tags/v${version}" \
        | jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | .digest // empty' \
        | sed 's/^sha256://'
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

applied=false
summary=""

current_drop=$(get_current_drop_version)
latest_drop=$(fetch_latest_drop_version)

if [[ -n "$latest_drop" && "$current_drop" != "$latest_drop" ]]; then
    echo "Updating drop-app: $current_drop -> $latest_drop"
    rpm_asset="Drop.Desktop.Client-${latest_drop}-1.x86_64.rpm"
    rpm_url="https://github.com/${DROP_APP_REPO}/releases/download/v${latest_drop}/${rpm_asset}"
    rpm_sha256=$(fetch_drop_release_digest "$latest_drop" "$rpm_asset")
    if [[ -z "$rpm_sha256" ]]; then
        echo "Release digest missing; downloading ${rpm_asset} to calculate SHA256..."
        rpm_sha256=$(fetch_file_sha256 "$rpm_url" /tmp/drop-desktop-client.rpm)
    fi
    echo "RPM SHA256: $rpm_sha256"

    inplace "s|^DROP_APP_VERSION=.*|DROP_APP_VERSION=${latest_drop}|" "$PINS_FILE"
    inplace "s|^DROP_APP_RPM_X86_64_URL=.*|DROP_APP_RPM_X86_64_URL=${rpm_url}|" "$PINS_FILE"
    inplace "s|^DROP_APP_RPM_X86_64_SHA256=.*|DROP_APP_RPM_X86_64_SHA256=${rpm_sha256}|" "$PINS_FILE"
    rm -f /tmp/drop-desktop-client.rpm
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
