#!/bin/bash
set -euo pipefail

/usr/bin/ibus-daemon -d -r --panel=disable --emoji-extension=disable
exec dbus-run-session -- /usr/bin/steam "$@"
