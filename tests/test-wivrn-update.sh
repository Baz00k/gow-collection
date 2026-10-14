#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR=$(mktemp -d)
# shellcheck disable=SC2329 # Invoked via trap.
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT
mkdir -p "${WORK_DIR}/bin"
export FIXTURE_DIR="$WORK_DIR"

# No network: synthesize a release and the exact ZIP member installed by
# Dockerfile, and route curl requests to fixtures through PATH.
python3 - "$WORK_DIR" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
import zipfile

root = Path(sys.argv[1])
library = b"\x7fELF fixture IVRSystem_026"
with zipfile.ZipFile(root / "xrizer.zip", "w") as archive:
    archive.writestr("xrizer-v0.7/bin/linux64/vrclient.so", library)
digest = hashlib.sha256((root / "xrizer.zip").read_bytes()).hexdigest()
(root / "library.sha").write_text(hashlib.sha256(library).hexdigest())
(root / "zip.sha").write_text(digest)
(root / "wivrn.json").write_text(json.dumps({"tag_name": "v26.9"}))
(root / "xrizer.json").write_text(json.dumps({
    "tag_name": "v0.7",
    "assets": [{
        "name": "xrizer-v0.7.zip",
        "browser_download_url": "https://github.com/Supreeeme/xrizer/releases/download/v0.7/xrizer-v0.7.zip",
        "digest": "sha256:" + digest,
    }],
}))
PY

cat > "${WORK_DIR}/bin/curl" <<'SH'
#!/bin/bash
set -euo pipefail
OUTPUT=""
URL=""
while (( $# )); do
    case "$1" in
        -o) OUTPUT="$2"; shift 2 ;;
        https://*) URL="$1"; shift ;;
        *) shift ;;
    esac
done
case "$URL" in
    https://api.github.com/repos/WiVRn/WiVRn/releases/latest) FILE=wivrn.json ;;
    https://api.github.com/repos/Supreeeme/xrizer/releases/latest) FILE=xrizer.json ;;
    https://github.com/Supreeeme/xrizer/releases/download/v0.7/xrizer-v0.7.zip) FILE=xrizer.zip ;;
    https://github.com/WiVRn/WiVRn/archive/refs/tags/v26.10.tar.gz) FILE=wivrn.tar.gz ;;
    *) echo "Unexpected fixture URL: $URL" >&2; exit 22 ;;
esac
if [[ -n "$OUTPUT" ]]; then
    cp "${FIXTURE_DIR}/${FILE}" "$OUTPUT"
else
    cat "${FIXTURE_DIR}/${FILE}"
fi
SH
chmod +x "${WORK_DIR}/bin/curl"
export PATH="${WORK_DIR}/bin:${PATH}"
cp "${PROJECT_ROOT}/images/wivrn/build/pins.env" "${WORK_DIR}/original-pins"
# Fix the fixture's current versions independently of future committed bumps.
sed -i -e 's/^WIVRN_VERSION=.*/WIVRN_VERSION=26.9/' \
    -e 's/^XRIZER_VERSION=.*/XRIZER_VERSION=0.6/' "${WORK_DIR}/original-pins"
export PINS_FILE="${WORK_DIR}/pins.env"
export GITHUB_OUTPUT="${WORK_DIR}/output"
cp "${WORK_DIR}/original-pins" "$PINS_FILE"

bash "${PROJECT_ROOT}/images/wivrn/update/check.sh"
grep -qx 'update_available=true' "$GITHUB_OUTPUT"
: > "$GITHUB_OUTPUT"
bash "${PROJECT_ROOT}/images/wivrn/update/apply.sh"
grep -qx 'applied=true' "$GITHUB_OUTPUT"
grep -qx 'XRIZER_VERSION=0.7' "$PINS_FILE"
grep -qx "XRIZER_ZIP_SHA256=$(cat "${WORK_DIR}/zip.sha")" "$PINS_FILE"
grep -qx "XRIZER_VRCLIENT_SHA256=$(cat "${WORK_DIR}/library.sha")" "$PINS_FILE"
grep -qx 'XRIZER_ZIP_URL=https://github.com/Supreeeme/xrizer/releases/download/v0.7/xrizer-v0.7.zip' "$PINS_FILE"
diff <(grep -v '^XRIZER_' "${WORK_DIR}/original-pins") <(grep -v '^XRIZER_' "$PINS_FILE")
cp "$PINS_FILE" "${WORK_DIR}/updated-pins"

: > "$GITHUB_OUTPUT"
bash "${PROJECT_ROOT}/images/wivrn/update/check.sh"
grep -qx 'update_available=false' "$GITHUB_OUTPUT"
: > "$GITHUB_OUTPUT"
bash "${PROJECT_ROOT}/images/wivrn/update/apply.sh"
grep -qx 'applied=false' "$GITHUB_OUTPUT"
cmp "$PINS_FILE" "${WORK_DIR}/updated-pins"

# Stage a WiVRn bump too, then reject a bad xrizer digest. Neither dependency
# nor BASE_APP_IMAGE may be changed on failure.
printf '{"tag_name":"v26.10"}' > "${WORK_DIR}/wivrn.json"
printf 'WiVRn source fixture' > "${WORK_DIR}/wivrn.tar.gz"
cp "${WORK_DIR}/original-pins" "$PINS_FILE"
python3 - "${WORK_DIR}/xrizer.json" <<'PY'
import json
from pathlib import Path
import sys
p = Path(sys.argv[1])
release = json.loads(p.read_text())
release["assets"][0]["digest"] = "sha256:" + "0" * 64
p.write_text(json.dumps(release))
PY
: > "$GITHUB_OUTPUT"
if bash "${PROJECT_ROOT}/images/wivrn/update/apply.sh"; then
    echo "ERROR: accepted invalid release digest" >&2
    exit 1
fi
cmp "$PINS_FILE" "${WORK_DIR}/original-pins"
test ! -s "$GITHUB_OUTPUT"

# GitHub can omit an asset digest. Still reject a ZIP without the expected
# runtime member before committing any pins.
python3 - "$WORK_DIR" <<'PY'
import json
from pathlib import Path
import sys
import zipfile
root = Path(sys.argv[1])
p = root / "xrizer.json"
release = json.loads(p.read_text())
release["assets"][0].pop("digest")
p.write_text(json.dumps(release))
with zipfile.ZipFile(root / "xrizer.zip", "w") as archive:
    archive.writestr("wrong-layout/vrclient.so", b"\x7fELF IVRSystem_026")
PY
if bash "${PROJECT_ROOT}/images/wivrn/update/apply.sh"; then
    echo "ERROR: accepted incompatible ZIP layout" >&2
    exit 1
fi
cmp "$PINS_FILE" "${WORK_DIR}/original-pins"
test ! -s "$GITHUB_OUTPUT"

# A missing GitHub digest is supported: compute the archive hash locally,
# while still validating the library's layout and interface before applying.
python3 - "$WORK_DIR" <<'PY'
from pathlib import Path
import sys
import zipfile
root = Path(sys.argv[1])
with zipfile.ZipFile(root / "xrizer.zip", "w") as archive:
    archive.writestr("xrizer-v0.7/bin/linux64/vrclient.so", b"\x7fELF fixture IVRSystem_026")
PY
bash "${PROJECT_ROOT}/images/wivrn/update/apply.sh"
grep -qx 'applied=true' "$GITHUB_OUTPUT"
grep -qx 'WIVRN_VERSION=26.10' "$PINS_FILE"
grep -qx 'XRIZER_VERSION=0.7' "$PINS_FILE"
diff <(grep '^BASE_APP_IMAGE=' "${WORK_DIR}/original-pins") <(grep '^BASE_APP_IMAGE=' "$PINS_FILE")

# Do not announce an update that lacks the expected runtime asset.
printf '{"tag_name":"v0.8","assets":[]}' > "${WORK_DIR}/xrizer.json"
: > "$GITHUB_OUTPUT"
if bash "${PROJECT_ROOT}/images/wivrn/update/check.sh"; then
    echo "ERROR: accepted release without runtime asset" >&2
    exit 1
fi
test ! -s "$GITHUB_OUTPUT"
echo "WiVRn/xrizer updater tests passed"
