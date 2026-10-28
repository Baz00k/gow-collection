#!/usr/bin/env bash
# Check for drop-app dependency updates
# Checks: Drop release tag, UMU launcher release

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

DROP_APP_REPO="${DROP_APP_REPO:-Drop-OSS/drop}"
UMU_LAUNCHER_REPO="${UMU_LAUNCHER_REPO:-Open-Wine-Components/umu-launcher}"

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

get_current_drop_tag() {
    local tag
    tag=$(get_pin DROP_APP_TAG)
    # Older pins only carried the client version; assume the tag was just v<version>.
    echo "${tag:-v$(get_pin DROP_APP_VERSION)}"
}

fetch_latest_drop_tag() {
    # GitHub's "latest" endpoint skips releases flagged as pre-release, which is
    # intentional here: we follow what upstream marks shippable (v0.4.0-rc-6 is
    # published without the pre-release flag, the rc-1..rc-5 builds were not).
    curl -fsSL "https://api.github.com/repos/${DROP_APP_REPO}/releases/latest" | jq -r '.tag_name // empty'
}

fetch_latest_umu_tag() {
    # Keep the raw tag: it is part of the download URL even though UMU versions
    # are bare (1.4.4) while Drop tags carry a v prefix.
    curl -fsSL "https://api.github.com/repos/${UMU_LAUNCHER_REPO}/releases/latest" | jq -r '.tag_name // empty'
}

umu_asset_url() {
    local tag="$1" version="$2" flavour="$3"
    echo "https://github.com/${UMU_LAUNCHER_REPO}/releases/download/${tag}/umu-launcher-${version}.${flavour}.x86_64.rpm"
}

# Main
[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

updates=()
summary=""

# Check drop-app
echo "Checking drop-app..."
current_drop=$(get_current_drop_tag)
latest_drop=$(fetch_latest_drop_tag)

if [[ -n "$latest_drop" ]]; then
    if [[ "$current_drop" != "$latest_drop" ]]; then
        echo "Drop-app update available: ${current_drop} -> ${latest_drop}"
        updates+=("drop")
        summary+="### Drop App\n\nUpdated from ${current_drop} to ${latest_drop}.\n\n"
    else
        echo "Drop-app up to date"
    fi
else
    echo "Warning: Could not fetch latest drop-app release"
fi

# Check umu-launcher
echo "Checking umu-launcher..."
current_umu=$(get_pin UMU_LAUNCHER_VERSION)
umu_flavour=$(get_pin UMU_LAUNCHER_RPM_FLAVOUR)
pinned_umu_url=$(get_pin UMU_LAUNCHER_RPM_X86_64_URL)
latest_umu_tag=$(fetch_latest_umu_tag)
latest_umu="${latest_umu_tag#v}"

if [[ -n "$latest_umu" && -n "$umu_flavour" ]]; then
    # A flavour change (e.g. fc44 -> fc45 on a base bump) must regenerate the
    # pins even when the version itself is current.
    expected_umu_url=$(umu_asset_url "$latest_umu_tag" "$latest_umu" "$umu_flavour")
    if [[ "$current_umu" != "$latest_umu" ]]; then
        echo "umu-launcher update available: ${current_umu} -> ${latest_umu}"
        updates+=("umu")
        summary+="### UMU Launcher\n\nUpdated from ${current_umu} to ${latest_umu}.\n\n"
    elif [[ "$pinned_umu_url" != "$expected_umu_url" ]]; then
        echo "umu-launcher pin stale for flavour ${umu_flavour}: ${pinned_umu_url} -> ${expected_umu_url}"
        updates+=("umu")
        summary+="### UMU Launcher\n\nRegenerated ${latest_umu} pin for flavour ${umu_flavour}.\n\n"
    else
        echo "umu-launcher up to date"
    fi
elif [[ -z "$umu_flavour" ]]; then
    echo "Warning: UMU_LAUNCHER_RPM_FLAVOUR missing from $PINS_FILE"
else
    echo "Warning: Could not fetch latest umu-launcher release"
fi

# Output results
if [[ ${#updates[@]} -gt 0 ]]; then
    echo "update_available=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "update_available=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
