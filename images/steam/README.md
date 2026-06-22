# Steam

Steam packaged for Games on Whales / Wolf with gamescope, MangoHud, GameMode, and Decky Loader.

## Quick Start

```toml
[[profiles.apps]]
title = "Steam"
icon_png_path = "https://games-on-whales.github.io/wildlife/apps/steam/assets/icon.png"
start_virtual_compositor = true

[profiles.apps.runner]
type = "docker"
name = "WolfSteam"
image = "ghcr.io/Baz00k/gow-collection/steam:edge"
mounts = []
env = [
    "GAMESCOPE_STEAM_MODE=off",
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
    "Ulimits": [
      {"Name":"nofile", "Hard":10240, "Soft":10240},
      {"Name":"memlock", "Hard":-1, "Soft":-1},
      {"Name":"rtprio", "Hard":99, "Soft":99}
    ],
    "Privileged": false,
    "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
  }
}
\
"""
```

## Steam-Specific Features

- Steam installed from RPM Fusion.
- Gamescope session for Wolf streaming.
- MangoHud performance overlay.
- GameMode support.
- Decky Loader for SteamOS-style plugins.
- SteamOS compatibility stubs for power/session actions inside the container.

## Steam Modes

`GAMESCOPE_STEAM_MODE` controls the Steam UI mode:

| Value | Behavior                                                | Best for                                            |
| ----- | ------------------------------------------------------- | --------------------------------------------------- |
| `off` | Standard Big Picture mode                               | Library management and desktop-style Steam settings |
| `on`  | SteamOS/GamepadUI mode with gamescope Steam integration | Controller-first couch gaming                       |

SteamOS mode is the console-like experience, but `Switch to desktop` does not work in a container because there is no underlying desktop session.

## Configuration

| Variable                             | Default        | Description                                                   |
| ------------------------------------ | -------------- | ------------------------------------------------------------- |
| `GAMESCOPE_WIDTH`                    | `1920`         | Stream display width                                          |
| `GAMESCOPE_HEIGHT`                   | `1080`         | Stream display height                                         |
| `GAMESCOPE_GAME_WIDTH`               | same as width  | Game resolution advertised by gamescope                       |
| `GAMESCOPE_GAME_HEIGHT`              | same as height | Game resolution advertised by gamescope                       |
| `GAMESCOPE_REFRESH`                  | `60`           | Refresh rate in Hz                                            |
| `GAMESCOPE_MODE`                     | `-b`           | Gamescope window mode (`-b` borderless, `-f` fullscreen)      |
| `GAMESCOPE_FORCE_WINDOWS_FULLSCREEN` | `off`          | `on` adds gamescope's `--force-windows-fullscreen` workaround |
| `STEAM_STARTUP_FLAGS`                | `-bigpicture`  | Flags passed to Steam                                         |
| `GAMESCOPE_STEAM_MODE`               | `off`          | `on` for SteamOS/GamepadUI mode                               |

Common variables such as `PUID`, `PGID`, and `GOW_DEBUG` are documented in [common runtime](../../docs/common-runtime.md).

## MangoHud

| Shortcut            | Function                         |
| ------------------- | -------------------------------- |
| `Right Shift + F12` | Toggle overlay on/off            |
| `Right Shift + F11` | Change position (corners/center) |
| `Right Shift + F10` | Toggle preset verbosity          |

In standard mode (`GAMESCOPE_STEAM_MODE=off`), MangoHud injects directly into games. In SteamOS mode, it runs as MangoApp through gamescope; FPS stats may freeze or show wrong values even when the game is running normally.

## Known Limitations

- In standard mode, Steam's desktop menu bar dropdowns may not open under gamescope. Use Big Picture settings where possible.
- In SteamOS mode, `Switch to desktop` does not work because there is no desktop session behind Steam.
- Steam uses file locks. Do not run two Steam containers against the same data directory.
- Some games only use a few CPU threads unless launched through GameMode. Add `gamemoderun %command%` to the game's Steam launch options if needed.

## Migration From Upstream GoW Steam

This image uses Valve's standard data layout: `~/.steam/steam` points to `~/.local/share/Steam/`.

On first boot, the image detects the old upstream GoW layout and migrates it. The two images should not share the same data directory after migration. Use separate Wolf profiles if you need to switch between them.

## Updates

Steam itself updates through Steam. Decky Loader pins are tracked in `build/pins.env` and updated by this image's update scripts.
