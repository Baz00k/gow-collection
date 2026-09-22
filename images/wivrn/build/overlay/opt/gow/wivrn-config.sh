#!/bin/bash
set -euo pipefail

# Generates ~/.config/wivrn/config.json from WIVRN_* environment variables.
# Values here override the system defaults in /etc/wivrn/config.json because
# WiVRn reads the user config last. Exits non-zero on invalid values so
# typos fail fast instead of silently leaving the headset unable to connect.

# shellcheck source=/dev/null
source /opt/gow/logging.sh

WIVRN_ENCODER="${WIVRN_ENCODER:-auto}"
WIVRN_CODEC="${WIVRN_CODEC:-}"
WIVRN_TCP_ONLY="${WIVRN_TCP_ONLY:-false}"
WIVRN_PUBLISH="${WIVRN_PUBLISH:-avahi}"
WIVRN_PORT="${WIVRN_PORT:-9757}"
WIVRN_APPLICATION="${WIVRN_APPLICATION:-}"
# NOTE: the compat path must be the directory containing bin/linux64/vrclient.so
# (what VR_OVERRIDE and openvrpaths.vrpath "runtime" point at). Fedora's
# opencomposite package nests it one level down: /usr/lib64/opencomposite/runtime.
WIVRN_OPENVR_COMPAT_PATH="${WIVRN_OPENVR_COMPAT_PATH:-/usr/lib64/opencomposite/runtime}"

if ! [[ "${WIVRN_PORT}" =~ ^[0-9]+$ ]]; then
    log_error "WIVRN_PORT must be numeric, got: '${WIVRN_PORT}'"
    exit 1
fi

CONFIG_DIR="${HOME:-/home/retro}/.config/wivrn"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "${CONFIG_DIR}"

export WIVRN_ENCODER WIVRN_CODEC WIVRN_TCP_ONLY WIVRN_PUBLISH WIVRN_PORT WIVRN_APPLICATION WIVRN_OPENVR_COMPAT_PATH CONFIG_FILE

/usr/bin/python3 <<'PY'
import json
import os
import sys

VALID_ENCODERS = ("auto", "x264", "nvenc", "vaapi", "vulkan")
VALID_CODECS = ("auto", "h264", "h265", "av1", "raw")

encoder = os.environ.get("WIVRN_ENCODER", "auto").strip().lower()
codec = os.environ.get("WIVRN_CODEC", "").strip().lower()
tcp_only_raw = os.environ.get("WIVRN_TCP_ONLY", "false").strip().lower()
publish_raw = os.environ.get("WIVRN_PUBLISH", "avahi").strip().lower()
port_raw = os.environ.get("WIVRN_PORT", "9757").strip()
application_raw = os.environ.get("WIVRN_APPLICATION", "").strip()
compat_raw = os.environ.get("WIVRN_OPENVR_COMPAT_PATH", "/usr/lib64/opencomposite/runtime").strip()
config_file = os.environ["CONFIG_FILE"]


def fail(message):
    print(f"[ERROR] wivrn-config: {message}", file=sys.stderr)
    sys.exit(1)


if encoder not in VALID_ENCODERS:
    fail(f"WIVRN_ENCODER must be one of {', '.join(VALID_ENCODERS)}, got: '{encoder}'")

if codec and codec not in VALID_CODECS:
    fail(f"WIVRN_CODEC must be one of {', '.join(VALID_CODECS)}, got: '{codec}'")

if tcp_only_raw in ("1", "true", "yes", "on"):
    tcp_only = True
elif tcp_only_raw in ("0", "false", "no", "off"):
    tcp_only = False
else:
    fail(f"WIVRN_TCP_ONLY must be a boolean (true/false), got: '{tcp_only_raw}'")

if publish_raw == "avahi":
    publish_service = "avahi"
elif publish_raw in ("off", "none", "null", "disabled"):
    publish_service = None
else:
    fail(f"WIVRN_PUBLISH must be 'avahi' or 'off', got: '{publish_raw}'")

config = {
    "port": int(port_raw),
    "tcp-only": tcp_only,
    "publish-service": publish_service,
}

if codec:
    if encoder == "auto":
        config["encoder"] = {"codec": codec}
    else:
        config["encoder"] = {"encoder": encoder, "codec": codec}
elif encoder != "auto":
    config["encoder"] = encoder

if compat_raw.lower() in ("", "auto"):
    pass
elif compat_raw.lower() in ("off", "none", "null", "disabled"):
    config["openvr-compat-path"] = None
elif compat_raw.startswith("/"):
    config["openvr-compat-path"] = compat_raw
else:
    fail(f"WIVRN_OPENVR_COMPAT_PATH must be an absolute path, 'auto', or 'off', got: '{compat_raw}'")

if application_raw:
    if application_raw.startswith("["):
        try:
            application = json.loads(application_raw)
        except json.JSONDecodeError as exc:
            fail(f"WIVRN_APPLICATION is not valid JSON: {exc}")
        if not isinstance(application, list) or not application:
            fail("WIVRN_APPLICATION JSON must be a non-empty array of strings")
        config["application"] = application
    else:
        config["application"] = application_raw

with open(config_file, "w", encoding="utf-8") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
PY

log_info "Wrote WiVRn config to ${CONFIG_FILE}"
