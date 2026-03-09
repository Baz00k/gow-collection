#!/bin/bash
set -euo pipefail

# Inline GoW utility functions (no base-app dependency)
gow_log() { echo "$(date +"[%Y-%m-%d %H:%M:%S]") $*"; }
gow_error() { echo -e "\033[0;31m[ERROR]\033[0m $*"; }

gow_log "Steam startup.sh"

# Apply performance tunings (sysctl) where container capabilities permit
# launch-comp.sh exits 0 with graceful degradation if permissions insufficient
/opt/gow/launch-comp.sh || true

# Recursively creating Steam necessary folders
# https://github.com/ValveSoftware/steam-for-linux/issues/6492
mkdir -p "$HOME/.steam/ubuntu12_32/steam-runtime"

# Use big picture mode by default
STEAM_STARTUP_FLAGS=${STEAM_STARTUP_FLAGS:-"-bigpicture"}

# Some game fixes taken from the Steam Deck
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0

# Enable Mangoapp
# Note: Ubuntus Mangoapp doesn't support Presets, so disable this for now
#export STEAM_MANGOAPP_PRESETS_SUPPORTED=1
export STEAM_USE_MANGOAPP=1
export MANGOHUD_CONFIGFILE=$(mktemp /tmp/mangohud.XXXXXXXX)
# Enable horizontal mangoapp bar
export STEAM_MANGOAPP_HORIZONTAL_SUPPORTED=1

# Enable Variable Rate Shading
# Note: this only works on gallium drivers and with new enough mesa
#       unfortunately there is no good way to check and disable this flag otherwise
export STEAM_USE_DYNAMIC_VRS=1
export RADV_FORCE_VRS_CONFIG_FILE=$(mktemp /tmp/radv_vrs.XXXXXXXX)
# To expose vram info from radv
export WINEDLLOVERRIDES=dxgi=n

# Initially write no_display to our config file
# so we don't get mangoapp showing up before Steam initializes
# on OOBE and stuff.
mkdir -p "$(dirname "$MANGOHUD_CONFIGFILE")"
echo "position=top-right" > "$MANGOHUD_CONFIGFILE"
echo "no_display" >> "$MANGOHUD_CONFIGFILE"

# Prepare our initial VRS config file
# for dynamic VRS in Mesa.
mkdir -p "$(dirname "$RADV_FORCE_VRS_CONFIG_FILE")"
# By default don't do half shading
echo "1x1" > "$RADV_FORCE_VRS_CONFIG_FILE"

# Scaling support
export STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT=1

# Have SteamRT's xdg-open send http:// and https:// URLs to Steam
export SRT_URLOPEN_PREFER_STEAM=1

# Set input method modules for Qt/GTK that will show the Steam keyboard
export QT_IM_MODULE=steam
export GTK_IM_MODULE=Steam


if [ -n "${RUN_GAMESCOPE:-}" ]; then
  # Enable support for xwayland isolation per-game in Steam
  # Note: This breaks without the additional steamdeck flags
  #export STEAM_MULTIPLE_XWAYLANDS=1
  #STEAM_STARTUP_FLAGS="${STEAM_STARTUP_FLAGS} -steamos3 -steamdeck -steampal"

  # We no longer need to set GAMESCOPE_EXTERNAL_OVERLAY from steam, mangoapp now does it itself
  export STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND=1

  # Setup socket for gamescope statistics shown in mango and steam
  # Create run directory file for startup and stats sockets
  tmpdir="$([[ -n "${XDG_RUNTIME_DIR+x}" ]] && mktemp -p "$XDG_RUNTIME_DIR" -d -t gamescope.XXXXXXX)"
  socket="${tmpdir:+$tmpdir/startup.socket}"
  stats="${tmpdir:+$tmpdir/stats.pipe}"
  # Fail early if we don't have a proper runtime directory setup
  if [[ -z $tmpdir || -z ${XDG_RUNTIME_DIR+x} ]]; then
    echo >&2 "!! Failed to find run directory in which to create stats session sockets (is \$XDG_RUNTIME_DIR set?)"
    exit 1
  fi

  export GAMESCOPE_STATS="$stats"
  mkfifo -- "$stats"
  mkfifo -- "$socket"

  # Attempt to claim global session if we're the first one running (e.g. /run/1000/gamescope)
  linkname="gamescope-stats"
  # shellcheck disable=SC2031
  sessionlink="${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/}${linkname}"
  lockfile="$sessionlink".lck
  exec 9>"$lockfile"
  if flock -n 9 && rm -f "$sessionlink" && ln -sf "$tmpdir" "$sessionlink"; then
    # Took the lock.  Don't blow up if those commands fail, though.
    echo >&2 "Claimed global gamescope stats session at \"$sessionlink\""
  else
    echo >&2 "!! Failed to claim global gamescope stats session"
  fi

  GAMESCOPE_WIDTH=${GAMESCOPE_WIDTH:-1920}
  GAMESCOPE_HEIGHT=${GAMESCOPE_HEIGHT:-1080}
  GAMESCOPE_REFRESH=${GAMESCOPE_REFRESH:-60}
  GAMESCOPE_MODE=${GAMESCOPE_MODE:-"-b"}

  # Launch gamescope
  # Fedora uses /usr/bin/gamescope (not /usr/games/gamescope)
  # shellcheck disable=SC2086
  /usr/bin/gamescope -e ${GAMESCOPE_MODE} -R "$socket" -T "$stats" -W "${GAMESCOPE_WIDTH}" -H "${GAMESCOPE_HEIGHT}" -r "${GAMESCOPE_REFRESH}" &

  # Read the variables we need from the socket
  if read -r -t 3 response_x_display response_wl_display <> "$socket"; then
    export DISPLAY="$response_x_display"
    export GAMESCOPE_WAYLAND_DISPLAY="$response_wl_display"
    unset WAYLAND_DISPLAY
    # We're done!
    gow_log "Gamescope started: DISPLAY=$DISPLAY"
  else
    echo "gamescope failed"
    exit 1
  fi

  # Start IBus to enable showing the steam on-screen keyboard
  /usr/bin/ibus-daemon -d -r --panel=disable --emoji-extension=disable
  
  # Launch mangoapp in background
  mangoapp &

  # Start Steam with dbus-run-session
  # Fedora uses /usr/bin/steam (not /usr/games/steam)
  # shellcheck disable=SC2086
  dbus-run-session -- /usr/bin/steam ${STEAM_STARTUP_FLAGS}
else
  gow_error "RUN_GAMESCOPE environment variable is not set."
  gow_error ""
  gow_error "This Docker image is designed for console-style gaming via gamescope."
  gow_error "Direct Steam launch without gamescope is not supported."
  gow_error ""
  gow_error "How to fix:"
  gow_error "  Set RUN_GAMESCOPE=1 in your Docker environment or Wolf apps.toml:"
  gow_error "    docker run -e RUN_GAMESCOPE=1 ..."
  gow_error "    [apps.steam.runner.env = [\"RUN_GAMESCOPE=1\"]]"
  gow_error ""
  gow_error "Why gamescope is required:"
  gow_error "  - Provides frame pacing and tear-free rendering"
  gow_error "  - Handles display scaling for different resolutions"
  gow_error "  - Enables MangoHud overlay integration"
  gow_error "  - Manages Wayland/X11 display server for Steam"
  exit 1
fi
