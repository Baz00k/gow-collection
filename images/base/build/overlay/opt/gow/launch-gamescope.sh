#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh
source /opt/gow/gamescope-lib.sh

if [[ "$#" -eq 0 ]]; then
    log_error "Usage: /opt/gow/launch-gamescope.sh <command> [args...]"
    exit 1
fi

gamescope_require_runtime_dir

GAMESCOPE_ARGS=()
gamescope_append_base_args GAMESCOPE_ARGS
gamescope_append_extra_args GAMESCOPE_ARGS

log_info "Starting gamescope session"
exec /usr/bin/gamescope "${GAMESCOPE_ARGS[@]}" -- "$@"
