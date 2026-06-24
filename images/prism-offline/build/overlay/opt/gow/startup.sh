#!/bin/bash
set -euo pipefail

source /opt/gow/logging.sh

log_info "Starting PrismLauncher"
exec /opt/gow/launch-gamescope.sh prismlauncher
