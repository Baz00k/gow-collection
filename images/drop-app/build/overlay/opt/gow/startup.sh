#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

log_info "Starting Drop App"
exec /opt/gow/launch-gamescope.sh /usr/bin/drop-app
