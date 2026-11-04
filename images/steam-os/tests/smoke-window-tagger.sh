#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/baz00k/gow-collection/steam-os:test}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam-os}"
EVIDENCE_FILE="${EVIDENCE_DIR}/window-tagger.txt"

mkdir -p "${EVIDENCE_DIR}"
printf '=== Smoke Test: Steam Game Window Tagger ===\nImage: %s\n\n' "${IMAGE_NAME}" > "${EVIDENCE_FILE}"

# Runs the real tagger with fake X tools that record the display they were
# called on. Steam's UI is on :42 and games on :73, as with two gamescope Xwaylands.
# shellcheck disable=SC2016 # Expanded inside the container.
TAGGER_SCRIPT='
set -euo pipefail
bin="$(mktemp -d)"

cat > "${bin}/pgrep" <<"STUB"
#!/bin/bash
echo "123 reaper SteamLaunch AppId=4242 -- game"
STUB

cat > "${bin}/xwininfo" <<"STUB"
#!/bin/bash
echo "xwininfo DISPLAY=${DISPLAY}" >> /tmp/x-calls
echo "     0x400001 \"game\": (\"steam_app_0\" \"steam_app_0\")  1920x1080+0+0  +0+0"
STUB

cat > "${bin}/xprop" <<"STUB"
#!/bin/bash
echo "xprop DISPLAY=${DISPLAY} $*" >> /tmp/x-calls
if [[ "$*" == "-id 0x400001 WM_CLASS" ]]; then
    echo "WM_CLASS(STRING) = \"steam_app_0\", \"steam_app_0\""
fi
STUB

chmod +x "${bin}"/*
DISPLAY=:42 STEAM_GAME_DISPLAY_0=:73 \
    PGREP_BIN="${bin}/pgrep" XWININFO_BIN="${bin}/xwininfo" XPROP_BIN="${bin}/xprop" \
    timeout 3 /opt/gow/steam-game-window-tagger.sh >/dev/null 2>&1 || true
cat /tmp/x-calls
'

OUTPUT="$(docker run --rm --entrypoint "" "${IMAGE_NAME}" bash -c "${TAGGER_SCRIPT}" 2>&1)"
printf '%s\n' "${OUTPUT}" >> "${EVIDENCE_FILE}"

if ! grep -qxF "xprop DISPLAY=:73 -id 0x400001 -f STEAM_GAME 32c -set STEAM_GAME 4242" <<< "${OUTPUT}"; then
    echo "RESULT: FAILED (game window was not tagged on the game display)" >> "${EVIDENCE_FILE}"
    echo "[ERROR] Steam game window tagger did not tag the window on STEAM_GAME_DISPLAY_0" >&2
    exit 1
fi

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
echo "[INFO] Steam game window tagger smoke test passed"
