#!/bin/bash
set -e

# Raise the open-file limit to avoid "Too many open files" (os error 24)
# during game downloads. The default Docker limit (1024) is too low for
# games with thousands of files. See: https://github.com/Drop-OSS/drop-app/issues/127
ulimit -n 65536 2>/dev/null || true

source /opt/gow/launch-comp.sh
launcher /usr/bin/drop-app
