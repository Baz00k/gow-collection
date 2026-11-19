#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/baz00k/gow-collection/steam-os:test}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam-os}"
EVIDENCE_FILE="${EVIDENCE_DIR}/fonts.txt"

mkdir -p "${EVIDENCE_DIR}"
printf '=== Smoke Test: CJK Fonts ===\nImage: %s\n\n' "${IMAGE_NAME}" > "${EVIDENCE_FILE}"

# Steam, Plasma and Discover render Japanese, Chinese and Korean text through
# fontconfig. Every language must resolve to the bundled Noto Sans CJK font.
# shellcheck disable=SC2016 # Expanded inside the container.
FONT_SCRIPT='
set -euo pipefail
for lang in ja zh ko; do
    family="$(fc-list ":lang=${lang}" family | grep -m1 "Noto Sans CJK" || true)"
    if [[ -z "${family}" ]]; then
        echo "lang=${lang}: no Noto Sans CJK coverage" >&2
        exit 1
    fi
    echo "lang=${lang}: ${family}"
done
'

if ! OUTPUT="$(docker run --rm --entrypoint "" "${IMAGE_NAME}" bash -c "${FONT_SCRIPT}" 2>&1)"; then
    printf '%s\n' "${OUTPUT}" >> "${EVIDENCE_FILE}"
    echo "RESULT: FAILED (CJK font coverage missing)" >> "${EVIDENCE_FILE}"
    echo "[ERROR] CJK fallback fonts are missing; see ${EVIDENCE_FILE}" >&2
    exit 1
fi
printf '%s\n' "${OUTPUT}" >> "${EVIDENCE_FILE}"

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
echo "[INFO] CJK font smoke test passed"
