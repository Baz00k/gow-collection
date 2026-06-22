#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

# Raise the open-file limit to avoid "Too many open files" (os error 24)
# during game downloads. The default Docker limit (1024) is too low for
# games with thousands of files. See: https://github.com/Drop-OSS/drop-app/issues/127
if ulimit -n 65536 2>/dev/null; then
    log_info "Raised open-file limit to $(ulimit -n)"
else
    log_warn "Could not raise open-file limit; continuing with $(ulimit -n)"
fi

log_info "Starting Drop App"
exec /usr/bin/drop-app
