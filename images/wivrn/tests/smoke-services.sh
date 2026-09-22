#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:-ghcr.io/baz00k/gow-collection/wivrn:test}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${SCRIPT_DIR}/../../../test-results/wivrn}"
EVIDENCE_FILE="${EVIDENCE_DIR}/services.txt"
STUB_DIR=""
CFG_DIR=""
CFG_DEFAULTS_DIR=""

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

mkdir -p "${EVIDENCE_DIR}"
{
    echo "=== Smoke Test: WiVRn Services ==="
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "Image: ${IMAGE_NAME}"
    echo ""
} > "${EVIDENCE_FILE}"

# shellcheck disable=SC2329 # Invoked via trap.
# Files created by the container are root-owned (PUID=0 runs), so plain rm
# can fail for non-root users. Fix ownership via a throwaway container first.
remove_dir() {
    local dir="$1"
    if [[ -z "${dir}" || ! -e "${dir}" ]]; then
        return 0
    fi
    if rm -rf "${dir}" 2>/dev/null; then
        return 0
    fi
    docker run --rm \
        --entrypoint "" \
        -v "${dir}:/clean" \
        "${IMAGE_NAME}" \
        chown -R "$(id -u):$(id -g)" /clean >/dev/null 2>&1 || true
    rm -rf "${dir}" 2>/dev/null || true
}

cleanup() {
    if [[ -n "${STUB_DIR}" ]]; then
        remove_dir "${STUB_DIR}"
    fi
    if [[ -n "${CFG_DIR}" ]]; then
        remove_dir "${CFG_DIR}"
    fi
    if [[ -n "${CFG_DEFAULTS_DIR}" ]]; then
        remove_dir "${CFG_DEFAULTS_DIR}"
    fi
}
trap cleanup EXIT

fail() {
    log_error "$1"
    echo "RESULT: FAILED ($1)" >> "${EVIDENCE_FILE}"
    exit 1
}

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    fail "image not found"
fi

# --- Part 1: wivrn-config.sh generates the expected JSON ----------------------
log_info "Checking WiVRn config generation..."
CFG_DIR="$(mktemp -d "${EVIDENCE_DIR}/wivrn-cfg.XXXXXX")"
CFG_DEFAULTS_DIR="$(mktemp -d "${EVIDENCE_DIR}/wivrn-cfg-defaults.XXXXXX")"

if ! docker run --rm \
    --entrypoint /opt/gow/wivrn-config.sh \
    -e HOME=/tmp/wivrn-cfg \
    -e WIVRN_ENCODER=vaapi \
    -e WIVRN_CODEC=h265 \
    -e WIVRN_TCP_ONLY=true \
    -e WIVRN_PUBLISH=off \
    -e WIVRN_PORT=19757 \
    -e 'WIVRN_APPLICATION=["steam", "steam://launch/275850/VR"]' \
    -v "${CFG_DIR}:/tmp/wivrn-cfg" \
    "${IMAGE_NAME}" >> "${EVIDENCE_FILE}" 2>&1; then
    fail "wivrn-config.sh failed with explicit env"
fi

if ! /usr/bin/python3 - "${CFG_DIR}/.config/wivrn/config.json" >> "${EVIDENCE_FILE}" 2>&1 <<'PY'; then
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)
print(json.dumps(config, indent=2))
assert config["port"] == 19757, config
assert config["tcp-only"] is True, config
assert config["publish-service"] is None, config
assert config["encoder"] == {"encoder": "vaapi", "codec": "h265"}, config
assert config["application"] == ["steam", "steam://launch/275850/VR"], config
assert config["openvr-compat-path"] == "/usr/lib64/opencomposite/runtime", config
PY
    fail "generated WiVRn config does not match explicit env"
fi
echo "explicit config: ok" >> "${EVIDENCE_FILE}"

if ! docker run --rm \
    --entrypoint /opt/gow/wivrn-config.sh \
    -e HOME=/tmp/wivrn-cfg-defaults \
    -v "${CFG_DEFAULTS_DIR}:/tmp/wivrn-cfg-defaults" \
    "${IMAGE_NAME}" >> "${EVIDENCE_FILE}" 2>&1; then
    fail "wivrn-config.sh failed with default env"
fi

if ! /usr/bin/python3 - "${CFG_DEFAULTS_DIR}/.config/wivrn/config.json" >> "${EVIDENCE_FILE}" 2>&1 <<'PY'; then
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)
print(json.dumps(config, indent=2))
assert config["port"] == 9757, config
assert config["tcp-only"] is False, config
assert config["publish-service"] == "avahi", config
assert config["openvr-compat-path"] == "/usr/lib64/opencomposite/runtime", config
assert "encoder" not in config, config
assert "application" not in config, config
PY
    fail "generated WiVRn config does not match defaults"
fi
echo "default config: ok" >> "${EVIDENCE_FILE}"

set +e
docker run --rm \
    --entrypoint /opt/gow/wivrn-config.sh \
    -e HOME=/tmp/wivrn-cfg-defaults \
    -e WIVRN_ENCODER=bogus \
    -v "${CFG_DEFAULTS_DIR}:/tmp/wivrn-cfg-defaults" \
    "${IMAGE_NAME}" >> "${EVIDENCE_FILE}" 2>&1
INVALID_EXIT_CODE=$?
set -e
if [[ ${INVALID_EXIT_CODE} -eq 0 ]]; then
    fail "wivrn-config.sh accepted an invalid WIVRN_ENCODER"
fi
echo "invalid config rejected: ok" >> "${EVIDENCE_FILE}"

# --- Part 2: service startup ordering and environment -------------------------
log_info "Checking service startup ordering..."
STUB_DIR="$(mktemp -d "${EVIDENCE_DIR}/services-stub.XXXXXX")"
SENTINEL_PATH="${STUB_DIR}/invoked"
RUN_LOG="${STUB_DIR}/docker-run.log"

cat > "${STUB_DIR}/dbus-run-session" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "dbus-run-session stub invoked" >> "${STARTUP_SENTINEL:?}"
if [[ "${1:-}" == "--" ]]; then
    shift
fi
exec "$@"
EOF
chmod +x "${STUB_DIR}/dbus-run-session"

for service in pipewire pipewire-pulse wireplumber; do
    cat > "${STUB_DIR}/${service}" <<EOF
#!/bin/bash
set -euo pipefail
echo "${service} stub invoked" >> "\${STARTUP_SENTINEL:?}"
EOF
    chmod +x "${STUB_DIR}/${service}"
done

cat > "${STUB_DIR}/wivrn-server" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "wivrn-server stub invoked" >> "${STARTUP_SENTINEL:?}"
echo "wivrn argv: $*" >> "${STARTUP_SENTINEL:?}"
echo "wivrn PULSE_SERVER: ${PULSE_SERVER:-unset}" >> "${STARTUP_SENTINEL:?}"
echo "wivrn VR_OVERRIDE: ${VR_OVERRIDE:-unset}" >> "${STARTUP_SENTINEL:?}"
echo "wivrn PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES: ${PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES:-unset}" >> "${STARTUP_SENTINEL:?}"
EOF
chmod +x "${STUB_DIR}/wivrn-server"

cat > "${STUB_DIR}/gamescope" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "gamescope stub invoked" >> "${STARTUP_SENTINEL:?}"
echo "gamescope argv: $*" >> "${STARTUP_SENTINEL:?}"
echo "gamescope PULSE_SERVER: ${PULSE_SERVER:-unset}" >> "${STARTUP_SENTINEL:?}"
echo "gamescope PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES: ${PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES:-unset}" >> "${STARTUP_SENTINEL:?}"
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
        shift
        exec "$@"
    fi
    shift
done
log_error() { echo "$*" >&2; }
log_error "gamescope stub: no -- separator in argv"
exit 1
EOF
chmod +x "${STUB_DIR}/gamescope"

cat > "${STUB_DIR}/steam" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "steam stub invoked" >> "${STARTUP_SENTINEL:?}"
echo "steam argv: $*" >> "${STARTUP_SENTINEL:?}"
echo "steam PULSE_SERVER: ${PULSE_SERVER:-unset}" >> "${STARTUP_SENTINEL:?}"
echo "steam PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES: ${PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES:-unset}" >> "${STARTUP_SENTINEL:?}"
echo "steam VR_OVERRIDE: ${VR_OVERRIDE:-unset}" >> "${STARTUP_SENTINEL:?}"
EOF
chmod +x "${STUB_DIR}/steam"

set +e
docker run \
    --rm \
    -e PUID=0 \
    -e STARTUP_SENTINEL=/tmp/smoke/invoked \
    -e STEAM_STARTUP_FLAGS="--test-passthrough" \
    -e WIVRN_PORT=19757 \
    -e WIVRN_WAIT_TIMEOUT=1 \
    -e PATH=/tmp/smoke:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    -v "${STUB_DIR}:/tmp/smoke" \
    "${IMAGE_NAME}" > "${RUN_LOG}" 2>&1
RUN_EXIT_CODE=$?
set -e

{
    echo "=== services startup output ==="
    cat "${RUN_LOG}"
    echo "=== services stub output ==="
    if [[ -f "${SENTINEL_PATH}" ]]; then
        cat "${SENTINEL_PATH}"
    else
        echo "service stubs were not invoked"
    fi
} >> "${EVIDENCE_FILE}"

if [[ ${RUN_EXIT_CODE} -ne 0 ]]; then
    fail "services startup path failed"
fi

if [[ ! -f "${SENTINEL_PATH}" ]]; then
    fail "service stubs were not invoked"
fi

# The audio daemons start concurrently, so their relative order is up to the
# scheduler. Assert group ordering instead: session bus first, then the whole
# audio group, then wivrn-server, then gamescope, then steam.
line_of() {
    local line
    line="$(grep -n -x -F "$1" "${SENTINEL_PATH}" | head -1 | cut -d: -f1 || true)"
    echo "${line:-0}"
}

DBUS_LINE="$(line_of "dbus-run-session stub invoked")"
PIPEWIRE_LINE="$(line_of "pipewire stub invoked")"
PULSE_LINE="$(line_of "pipewire-pulse stub invoked")"
WIREPLUMBER_LINE="$(line_of "wireplumber stub invoked")"
WIVRN_LINE="$(line_of "wivrn-server stub invoked")"
GAMESCOPE_LINE="$(line_of "gamescope stub invoked")"
STEAM_LINE="$(line_of "steam stub invoked")"

for entry in "dbus:${DBUS_LINE}" "pipewire:${PIPEWIRE_LINE}" "pulse:${PULSE_LINE}" \
    "wireplumber:${WIREPLUMBER_LINE}" "wivrn:${WIVRN_LINE}" \
    "gamescope:${GAMESCOPE_LINE}" "steam:${STEAM_LINE}"; do
    if [[ "${entry#*:}" -le 0 ]]; then
        fail "missing services evidence: ${entry%%:*} stub invoked"
    fi
done

AUDIO_LAST="${PIPEWIRE_LINE}"
if [[ "${PULSE_LINE}" -gt "${AUDIO_LAST}" ]]; then AUDIO_LAST="${PULSE_LINE}"; fi
if [[ "${WIREPLUMBER_LINE}" -gt "${AUDIO_LAST}" ]]; then AUDIO_LAST="${WIREPLUMBER_LINE}"; fi

if ! [[ "${DBUS_LINE}" -lt "${PIPEWIRE_LINE}" && "${DBUS_LINE}" -lt "${PULSE_LINE}" \
    && "${DBUS_LINE}" -lt "${WIREPLUMBER_LINE}" && "${AUDIO_LAST}" -lt "${WIVRN_LINE}" \
    && "${WIVRN_LINE}" -lt "${GAMESCOPE_LINE}" && "${GAMESCOPE_LINE}" -lt "${STEAM_LINE}" ]]; then
    fail "service startup groups out of order"
fi
echo "service ordering: ok" >> "${EVIDENCE_FILE}"

# The OpenVR compat path (/usr/...) must be translated for the Pressure
# Vessel sandbox (/run/host prefix) so OpenVR games find OpenComposite
# instead of silently falling back to desktop mode (no HMD image, no
# tracking). Both wivrn-server (headset-initiated launches inherit its
# environment) and Steam must see the translated value.
for expected in \
    "gamescope argv: --backend wayland -b -w 1920 -h 1080 -W 1920 -H 1080 -r 60 -e --steam --mangoapp -- steam --test-passthrough" \
    "steam argv: --test-passthrough" \
    "steam PULSE_SERVER: unix:/run/user/0/pulse/native" \
    "steam PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES: 1" \
    "steam VR_OVERRIDE: /run/host/usr/lib64/opencomposite/runtime" \
    "wivrn VR_OVERRIDE: /run/host/usr/lib64/opencomposite/runtime" \
    "wivrn PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES: 1"; do
    if ! grep -qF "${expected}" "${SENTINEL_PATH}"; then
        fail "missing services evidence: ${expected}"
    fi
done
echo "service env and argv: ok" >> "${EVIDENCE_FILE}"

echo "RESULT: PASSED" >> "${EVIDENCE_FILE}"
log_info "WiVRn services smoke test passed"
exit 0
