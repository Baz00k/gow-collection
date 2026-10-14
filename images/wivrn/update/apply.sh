#!/usr/bin/env bash
# Apply WiVRn image dependency updates
# Updates: WiVRn and xrizer versions, URLs and SHA256 hashes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PINS_FILE="${PINS_FILE:-${SCRIPT_DIR}/../build/pins.env}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

inplace() {
    sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"
}

abort() { echo "ERROR: $1" >&2; exit 1; }

get_pin() {
    grep "^$1=" "$PINS_FILE" | head -1 | cut -d'=' -f2- || echo ""
}

get_wivrn_repo() {
    local repo
    repo=$(get_pin WIVRN_REPO)
    echo "${repo:-WiVRn/WiVRn}"
}

fetch_latest_wivrn_version() {
    local repo
    repo=$(get_wivrn_repo)
    curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty' | sed 's/^v//'
}

fetch_file_sha256() {
    local url="$1" output_file="$2"
    curl -fsSL "$url" -o "$output_file"
    sha256sum "$output_file" | cut -d' ' -f1
}

[[ ! -f "$PINS_FILE" ]] && abort "pins.env not found at $PINS_FILE"

# Stage both dependency updates; a bad download must not leave partial pins.
WORK_DIR=$(mktemp -d)
STAGED_PINS=$(mktemp "${PINS_FILE}.XXXXXX")
# shellcheck disable=SC2329 # Invoked via trap.
cleanup() {
    rm -f "$STAGED_PINS"
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
cp -p "$PINS_FILE" "$STAGED_PINS"

applied=false
summary=""

# --- WiVRn server ---
wivrn_repo=$(get_wivrn_repo)
current_wivrn=$(get_pin WIVRN_VERSION)
latest_wivrn=$(fetch_latest_wivrn_version)

if [[ -n "$latest_wivrn" && "$current_wivrn" != "$latest_wivrn" ]]; then
    echo "Updating WiVRn: $current_wivrn -> $latest_wivrn"
    wivrn_url="https://github.com/${wivrn_repo}/archive/refs/tags/v${latest_wivrn}.tar.gz"
    echo "Downloading WiVRn source tarball..."
    wivrn_sha=$(fetch_file_sha256 "$wivrn_url" "${WORK_DIR}/wivrn.tar.gz")
    echo "WiVRn tarball SHA256: $wivrn_sha"

    inplace "s|^WIVRN_VERSION=.*|WIVRN_VERSION=${latest_wivrn}|" "$STAGED_PINS"
    inplace "s|^WIVRN_TARBALL_URL=.*|WIVRN_TARBALL_URL=${wivrn_url}|" "$STAGED_PINS"
    inplace "s|^WIVRN_TARBALL_SHA256=.*|WIVRN_TARBALL_SHA256=${wivrn_sha}|" "$STAGED_PINS"

    applied=true
    summary+="### WiVRn\n\nUpdated from v${current_wivrn} to v${latest_wivrn}.\n\n"
fi

# --- xrizer ---
xrizer_repo=$(get_pin XRIZER_REPO)
xrizer_repo="${xrizer_repo:-Supreeeme/xrizer}"
current_xrizer=$(get_pin XRIZER_VERSION)
xrizer_release=$(curl -fsSL "https://api.github.com/repos/${xrizer_repo}/releases/latest")
latest_xrizer=$(jq -er '.tag_name | select(type == "string" and length > 0)' <<< "$xrizer_release")
latest_xrizer="${latest_xrizer#v}"
[[ "$latest_xrizer" =~ ^[0-9]+(\.[0-9]+)*$ ]] || abort "Unsupported xrizer version: $latest_xrizer"

if [[ "$current_xrizer" != "$latest_xrizer" ]]; then
    echo "Updating xrizer: $current_xrizer -> $latest_xrizer"
    xrizer_asset=$(jq -cer --arg asset "xrizer-v${latest_xrizer}.zip" \
        '[.assets[] | select(.name == $asset)] | if length == 1 then .[0] else error("Expected one xrizer runtime ZIP") end' <<< "$xrizer_release")
    xrizer_url=$(jq -er '.browser_download_url' <<< "$xrizer_asset")
    [[ "$xrizer_url" == "https://github.com/${xrizer_repo}/releases/download/v${latest_xrizer}/xrizer-v${latest_xrizer}.zip" ]] \
        || abort "Unexpected xrizer asset URL: $xrizer_url"
    xrizer_sha=$(fetch_file_sha256 "$xrizer_url" "${WORK_DIR}/xrizer.zip")
    xrizer_digest=$(jq -r '.digest // empty' <<< "$xrizer_asset")
    if [[ -n "$xrizer_digest" && "$xrizer_digest" != "sha256:${xrizer_sha}" ]]; then
        abort "xrizer ZIP does not match GitHub's release digest"
    fi
    # Read only the exact member Dockerfile installs; reject an incompatible
    # archive before committing pins. Never extract arbitrary ZIP paths.
    xrizer_vrclient_sha=$(python3 - "${WORK_DIR}/xrizer.zip" "$latest_xrizer" <<'PY'
import hashlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    member = f"xrizer-v{sys.argv[2]}/bin/linux64/vrclient.so"
    if archive.namelist().count(member) != 1:
        sys.exit(f"Expected one {member} in xrizer ZIP")
    library = archive.read(member)
    if not library.startswith(b"\x7fELF") or b"IVRSystem_026" not in library:
        sys.exit("xrizer runtime is not an ELF library with IVRSystem_026")
    print(hashlib.sha256(library).hexdigest())
PY
    )
    for pin in XRIZER_VERSION XRIZER_ZIP_URL XRIZER_ZIP_SHA256 XRIZER_VRCLIENT_SHA256; do
        grep -q "^${pin}=" "$STAGED_PINS" || abort "Missing pin: $pin"
    done
    inplace "s|^XRIZER_VERSION=.*|XRIZER_VERSION=${latest_xrizer}|" "$STAGED_PINS"
    inplace "s|^XRIZER_ZIP_URL=.*|XRIZER_ZIP_URL=${xrizer_url}|" "$STAGED_PINS"
    inplace "s|^XRIZER_ZIP_SHA256=.*|XRIZER_ZIP_SHA256=${xrizer_sha}|" "$STAGED_PINS"
    inplace "s|^XRIZER_VRCLIENT_SHA256=.*|XRIZER_VRCLIENT_SHA256=${xrizer_vrclient_sha}|" "$STAGED_PINS"
    applied=true
    summary+="### xrizer\n\nUpdated from v${current_xrizer} to v${latest_xrizer}.\n\n"
fi

if [[ "$applied" == "true" ]]; then
    mv "$STAGED_PINS" "$PINS_FILE"
    echo "Updated $PINS_FILE"
    cat "$PINS_FILE"
    echo "applied=true" >> "$GITHUB_OUTPUT"
    echo -e "summary_md<<EOF\n${summary%\\n}EOF" >> "$GITHUB_OUTPUT"
else
    echo "No updates to apply"
    echo "applied=false" >> "$GITHUB_OUTPUT"
    echo "summary_md=" >> "$GITHUB_OUTPUT"
fi
