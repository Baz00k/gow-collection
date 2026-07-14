# SteamOS

A SteamOS-style image for Games on Whales / Wolf, with Steam running in gamescope, KDE Plasma desktop mode, Flatpak, MangoHud, GameMode, and Decky Loader.

## Quick Start

```toml
[[profiles.apps]]
title = "SteamOS"
icon_png_path = "https://raw.githubusercontent.com/Baz00k/gow-collection/main/images/steam-os/assets/icon.png"
start_virtual_compositor = true

[profiles.apps.runner]
type = "docker"
name = "WolfSteamOS"
image = "ghcr.io/baz00k/gow-collection/steam-os:edge"
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
- Bounded automatic restart after a Steam crash.

## Sessions

The container starts in the Steam gaming session. Steam's `Switch to Desktop` action switches to KDE Plasma.
Use the `Return to Steam` desktop launcher in Plasma to switch back to Steam.

The Steam session uses gamescope's Steam integration mode.
The Plasma session runs as a nested KDE Wayland desktop on the Wolf compositor.

## Installing Apps

Use KDE Discover in desktop mode or use the CLI to install the apps you want.
The image does not bundle third-party launchers; Heroic, Lutris, Bottles, emulators, and similar apps are user choices.

Example:

```bash
flatpak install flathub com.heroicgameslauncher.hgl
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

## Caveats

- Steam's UI can be laggy in GamepadUI/Gaming Mode unless Steam GPU acceleration is enabled. Enable it from desktop mode: switch to KDE Plasma, open Steam, go to Settings, and enable GPU accelerated rendering in web views.
- Gaming performance in desktop mode can be noticeably worse than in Gaming Mode for some games. Add non-Steam games to Steam and launch them from Gaming Mode.
- Some games only use a few CPU threads unless launched through GameMode. Add `gamemoderun %command%` to the game's Steam launch options if needed.
- KDE Plasma runs nested inside Wolf's compositor. Some desktop compositor behavior may differ from a physical Steam Deck.
- Flatpak app installs depend on the container permissions and namespace support provided by the Wolf runner configuration.
- SteamOS update, BIOS update, and hardware power-management commands are compatibility stubs, not real host firmware or OS controls.
- Gamescope can lose keyboard modifier state in nested Wayland sessions. Affected games detect Left Shift or Control while rebinding, but do not see the modifier held during gameplay. This is tracked upstream in [gamescope #2032](https://github.com/ValveSoftware/gamescope/issues/2032) and the underlying nested-modifier issue [gamescope #266](https://github.com/ValveSoftware/gamescope/issues/266). The same symptom was previously reported to Wolf in [wolf #217](https://github.com/games-on-whales/wolf/issues/217).

## Existing Steam Data

Migration from the upstream GoW Steam image is not supported. Create a new Wolf
app/profile for this image and let Steam create a fresh data directory. Do not
share one Steam data directory between the two images.

## Updates

Steam itself updates through Steam. The image can be updated through the Wolf UI or CLI.
