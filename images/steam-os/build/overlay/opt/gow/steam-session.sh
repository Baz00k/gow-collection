#!/bin/bash
set -euo pipefail

/usr/bin/ibus-daemon -d -r --panel=disable --emoji-extension=disable || true
exec /usr/bin/steam "$@"
