# Steam

Steam packaged for Games on Whales / Wolf as a SteamOS-style session with gamescope, KDE Plasma desktop mode, Flatpak, MangoHud, GameMode, and Decky Loader.

## Quick Start

```toml
[[profiles.apps]]
title = "Steam"
icon_png_path = "https://games-on-whales.github.io/wildlife/apps/steam/assets/icon.png"
start_virtual_compositor = true

[profiles.apps.runner]
type = "docker"
name = "WolfSteam"
image = "ghcr.io/baz00k/gow-collection/steam:edge"
mounts = []
env = [
    "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
]
devices = []
ports = []
base_create_json = """
{
  "HostConfig": {
    "IpcMode": "host",
    "ShmSize": 8589934592,
    "CapAdd": ["SYS_ADMIN", "SYS_NICE", "SYS_PTRACE", "NET_RAW", "MKNOD", "NET_ADMIN"],
    "SecurityOpt": ["seccomp=unconfined", "apparmor=unconfined"],
    "MaskedPaths": [],
    "ReadonlyPaths": [],
    "Ulimits": [
      {"Name":"nofile", "Hard":10240, "Soft":10240},
      {"Name":"memlock", "Hard":-1, "Soft":-1},
      {"Name":"rtprio", "Hard":99, "Soft":99}
    ],
    "Privileged": false,
    "DeviceCgroupRules": ["c 13:* rwm", "c 244:* rwm"]
  }
}
\
"""
```

## Features

- SteamOS/GamepadUI session through gamescope by default.
- KDE Plasma desktop mode through Steam's session switch.
- Flatpak with Flathub configured for user-selected desktop apps.
- MangoHud performance overlay.
- GameMode support.
- Decky Loader for SteamOS-style plugins.
- SteamOS compatibility stubs for power/session actions inside the container.

## Sessions

The container starts in the Steam gaming session. Steam's `Switch to Desktop` action switches to KDE Plasma.
Use the `Return to Steam` desktop launcher in Plasma to switch back to Steam.

The Steam session uses gamescope's Steam integration mode.
The Plasma session runs as a nested KDE Wayland desktop on the Wolf compositor.

## Installing Apps

Use KDE Discover in desktop mode or use CLI to install the apps you want.
The image does not bundle third-party launchers; Heroic, Lutris, Bottles, emulators, and similar apps are user choices.

Example:

```bash
flatpak install --user flathub com.heroicgameslauncher.hgl
```

After installing another launcher or game, add it to Steam as a non-Steam game if you want it available from the gaming session.

## Configuration

| Variable                             | Default                                     | Description                                                         |
| ------------------------------------ | ------------------------------------------- | ------------------------------------------------------------------- |
| `STEAMOS_SESSION`                    | `gamescope`                                 | Initial session: `gamescope` or `plasma`                            |
| `GAMESCOPE_FORCE_WINDOWS_FULLSCREEN` | `off`                                       | `on` adds gamescope's `--force-windows-fullscreen` workaround       |
| `STEAM_WINDOW_TAGGER`                | `on`                                        | `off` disables tagging broken non-Steam game windows in gaming mode |
| `STEAM_STARTUP_FLAGS`                | `-gamepadui -steamos3 -steampal -steamdeck` | Flags passed to Steam                                               |

Shared variables such as `PUID`, `PGID`, `GOW_DEBUG`, and `GAMESCOPE_*` are documented in [common runtime](../../docs/common-runtime.md).

`STEAM_WINDOW_TAGGER=on` starts a small gaming-mode-only helper that works around non-Steam launchers whose game windows keep `steam_app_0` instead of the active Steam AppId.
Without that AppId, gamescope's Steam mode can leave the game behind Steam's loading screen.
Set `STEAM_WINDOW_TAGGER=off` if the workaround causes problems or you want the unmodified Steam/gamescope behavior.

## MangoHud

| Shortcut            | Function                         |
| ------------------- | -------------------------------- |
| `Right Shift + F12` | Toggle overlay on/off            |
| `Right Shift + F11` | Change position (corners/center) |
| `Right Shift + F10` | Toggle preset verbosity          |

MangoHud runs as MangoApp through gamescope. FPS stats may freeze or show wrong values even when the game is running normally.

## Known Limitations

- SteamOS update, BIOS update, and hardware power-management commands are compatibility stubs, not real host firmware or OS controls.
- KDE Plasma runs nested inside Wolf's compositor. Some desktop compositor behavior may differ from a physical Steam Deck.
- Flatpak app installs depend on the container permissions and namespace support provided by the Wolf runner configuration.
- Steam uses file locks. Do not run two Steam containers against the same data directory.
- Some games only use a few CPU threads unless launched through GameMode. Add `gamemoderun %command%` to the game's Steam launch options if needed.

## Migration From Upstream GoW Steam

This image uses Valve's standard data layout: `~/.steam/steam` points to `~/.local/share/Steam/`.

On first boot, the image detects the old upstream GoW layout and migrates it.
The two images should not share the same data directory after migration. Use separate Wolf profiles if you need to switch between them.

## Updates

Steam itself updates through Steam. The image can be updated through the Wolf UI or CLI.
