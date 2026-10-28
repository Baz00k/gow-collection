#!/usr/bin/env bash
# Apply drop-app dependency updates
# Updates: Drop release tag, client version, RPM URL and SHA256
#          UMU launcher version, RPM URL and SHA256

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

DROP_APP_REPO="${DROP_APP_REPO:-Drop-OSS/drop}"
UMU_LAUNCHER_REPO="${UMU_LAUNCHER_REPO:-Open-Wine-Components/umu-launcher}"

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

fetch_latest_umu_tag() {
    # Keep the raw tag: it is part of the download URL even though UMU versions
    # are bare (1.4.4) while Drop tags carry a v prefix.
    curl -fsSL "https://api.github.com/repos/${UMU_LAUNCHER_REPO}/releases/latest" | jq -r '.tag_name // empty'
}

umu_asset_url() {
    local tag="$1" version="$2" flavour="$3"
    echo "https://github.com/${UMU_LAUNCHER_REPO}/releases/download/${tag}/umu-launcher-${version}.${flavour}.x86_64.rpm"
}

fetch_release_json() {
    local repo="$1" tag="$2"
    curl -fsSL "https://api.github.com/repos/${repo}/releases/tags/${tag}"
}

asset_name() {
    local release_json="$1" pattern="$2"
    jq -r --arg pattern "$pattern" '.assets[].name | select(test($pattern))' <<< "$release_json" | head -1
}

asset_exists() {
    local release_json="$1" asset="$2"
    jq -e --arg asset "$asset" 'any(.assets[]; .name == $asset)' >/dev/null <<< "$release_json"
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

summary=""

# Phase 1: work out every update and validate it before touching pins.env, so a
# failure part-way through never leaves the file half updated.

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

umu_version=""
umu_url=""
umu_sha256=""

# Upstream ships one RPM per Fedora release, so the asset name is built from the
# version plus the pinned target flavour (e.g. fc44). Comparing the resolved URL
# as well as the version means a flavour bump alone also regenerates the pins.
current_umu=$(get_pin UMU_LAUNCHER_VERSION)
umu_flavour=$(get_pin UMU_LAUNCHER_RPM_FLAVOUR)
pinned_umu_url=$(get_pin UMU_LAUNCHER_RPM_X86_64_URL)
latest_umu_tag=$(fetch_latest_umu_tag)
latest_umu="${latest_umu_tag#v}"

if [[ -n "$latest_umu" ]]; then
    [[ -z "$umu_flavour" ]] && abort "UMU_LAUNCHER_RPM_FLAVOUR missing from $PINS_FILE"

    umu_url=$(umu_asset_url "$latest_umu_tag" "$latest_umu" "$umu_flavour")

    if [[ "$current_umu" != "$latest_umu" || "$pinned_umu_url" != "$umu_url" ]]; then
        echo "Resolving umu-launcher ${current_umu} -> ${latest_umu} (${umu_flavour})"
        umu_asset="umu-launcher-${latest_umu}.${umu_flavour}.x86_64.rpm"
        umu_json=$(fetch_release_json "$UMU_LAUNCHER_REPO" "$latest_umu_tag")

        if ! asset_exists "$umu_json" "$umu_asset"; then
            abort "release ${latest_umu_tag} has no ${umu_asset}; UMU_LAUNCHER_RPM_FLAVOUR (${umu_flavour}) needs updating"
        fi

        umu_version="$latest_umu"
        umu_sha256=$(resolve_digest "$umu_json" "$umu_asset" "$umu_url")
        echo "UMU launcher ${umu_version} (${umu_flavour}), SHA256 ${umu_sha256}"
    else
        umu_url=""
    fi
fi

# Phase 2: write the validated updates.
applied=false

if [[ -n "$drop_tag" ]]; then
    set_pin DROP_APP_VERSION "$drop_version"
    set_pin DROP_APP_TAG "$drop_tag" DROP_APP_VERSION
    set_pin DROP_APP_RPM_X86_64_URL "$drop_url"
    set_pin DROP_APP_RPM_X86_64_SHA256 "$drop_sha256"
    applied=true
    summary+="### Drop App\n\nUpdated from ${current_drop} to ${drop_tag} (client ${drop_version}).\n\n"
fi

if [[ -n "$umu_version" ]]; then
    set_pin UMU_LAUNCHER_VERSION "$umu_version"
    set_pin UMU_LAUNCHER_RPM_X86_64_URL "$umu_url"
    set_pin UMU_LAUNCHER_RPM_X86_64_SHA256 "$umu_sha256"
    applied=true
    if [[ "$current_umu" == "$umu_version" ]]; then
        summary+="### UMU Launcher\n\nRegenerated ${umu_version} pin for flavour ${umu_flavour}.\n\n"
    else
        summary+="### UMU Launcher\n\nUpdated from ${current_umu} to ${umu_version} (${umu_flavour}).\n\n"
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
