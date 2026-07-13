#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/baz00k/gow-collection/steam:test}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/steam}"
EVIDENCE_FILE="${EVIDENCE_DIR}/steam-wrapper.txt"
TEST_HOME=""

cleanup() {
    if [[ -n "${TEST_HOME}" ]]; then
        rm -rf "${TEST_HOME}"
    fi
}
trap cleanup EXIT

fail() {
    echo "RESULT: FAILED ($1)" >> "${EVIDENCE_FILE}"
    echo "[ERROR] $1" >&2
    exit 1
}

mkdir -p "${EVIDENCE_DIR}"
printf '=== Smoke Test: Steam Wrapper ===\nImage: %s\n\n' "${IMAGE_NAME}" > "${EVIDENCE_FILE}"

TEST_HOME="$(mktemp -d "${EVIDENCE_DIR}/steam-wrapper.XXXXXX")"
mkdir -p "${TEST_HOME}/.steam" "${TEST_HOME}/.local/share/Steam"

cat > "${TEST_HOME}/.local/share/Steam/steam.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
count_file="${HOME}/calls"
count=0
if [[ -f "${count_file}" ]]; then
    count="$(<"${count_file}")"
fi
((count += 1))
printf '%s\n' "${count}" > "${count_file}"
if (( count < 3 )); then
    exit 42
fi
exit 0
EOF
chmod +x "${TEST_HOME}/.local/share/Steam/steam.sh"

docker run --rm \
    --entrypoint /usr/bin/steam \
    -e HOME=/tmp/steam-home \
    -e STEAM_MAX_CRASH_RESTARTS=2 \
    -e STEAM_CRASH_RESTART_BASE_DELAY=0 \
    -e STEAM_CRASH_RESTART_MAX_DELAY=0 \
    -v "${TEST_HOME}:/tmp/steam-home" \
    "${IMAGE_NAME}" -gamepadui >> "${EVIDENCE_FILE}" 2>&1 || fail "Steam did not recover within the restart limit"

if [[ "$(<"${TEST_HOME}/calls")" != "3" ]]; then
    fail "Steam wrapper did not perform two bounded restarts"
fi

rm -f "${TEST_HOME}/calls"
cat > "${TEST_HOME}/.local/share/Steam/steam.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
count_file="${HOME}/calls"
count=0
if [[ -f "${count_file}" ]]; then
    count="$(<"${count_file}")"
fi
((count += 1))
printf '%s\n' "${count}" > "${count_file}"
exit 42
EOF
chmod +x "${TEST_HOME}/.local/share/Steam/steam.sh"

set +e
docker run --rm \
    --entrypoint /usr/bin/steam \
    -e HOME=/tmp/steam-home \
    -e STEAM_MAX_CRASH_RESTARTS=1 \
    -e STEAM_CRASH_RESTART_BASE_DELAY=0 \
    -e STEAM_CRASH_RESTART_MAX_DELAY=0 \
    -v "${TEST_HOME}:/tmp/steam-home" \
    "${IMAGE_NAME}" -gamepadui >> "${EVIDENCE_FILE}" 2>&1
exit_code=$?
set -e

if [[ ${exit_code} -ne 42 ]]; then
    fail "Steam wrapper did not return the final crash exit code"
fi
if [[ "$(<"${TEST_HOME}/calls")" != "2" ]]; then
    fail "Steam wrapper exceeded the configured restart limit"
fi

set +e
docker run --rm \
    --entrypoint /usr/bin/steam \
    -e HOME=/tmp/steam-home \
    -e STEAM_MAX_CRASH_RESTARTS=08 \
    -v "${TEST_HOME}:/tmp/steam-home" \
    "${IMAGE_NAME}" -gamepadui >> "${EVIDENCE_FILE}" 2>&1
exit_code=$?
set -e

if [[ ${exit_code} -eq 0 ]]; then
    fail "Steam wrapper accepted an invalid restart setting"
fi

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
echo "[PASS] Steam wrapper smoke test passed"
