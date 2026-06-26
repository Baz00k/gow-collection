# Steam

Steam packaged for Games on Whales / Wolf as a SteamOS-style session with gamescope, KDE Plasma desktop mode, Firefox, Flatpak, MangoHud, GameMode, and Decky Loader.

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

- Steam installed from RPM Fusion.
- SteamOS/GamepadUI session through gamescope by default.
- KDE Plasma desktop mode through Steam's session switch.
- Firefox browser in desktop mode.
- Flatpak with Flathub configured for user-selected desktop apps.
- MangoHud performance overlay.
- GameMode support.
- Decky Loader for SteamOS-style plugins.
- SteamOS compatibility stubs for power/session actions inside the container.

## Sessions

The container starts in the Steam gaming session. Steam's `Switch to Desktop` action switches to KDE Plasma. Use the `Return to Steam` desktop launcher in Plasma to switch back to Steam.

The Steam session uses gamescope's Steam integration mode. The Plasma session runs as a nested KDE Wayland desktop on the Wolf compositor.

For diagnostics, set `STEAMOS_SESSION=plasma` to start directly in desktop mode.

## Installing Apps

Use KDE Discover or Flatpak in desktop mode to install the apps you want. The image does not bundle third-party launchers; Heroic, Lutris, Bottles, emulators, and similar apps are user choices.

Example:

```bash
flatpak install --user flathub com.heroicgameslauncher.hgl
```

After installing another launcher or game, add it to Steam as a non-Steam game if you want it available from the gaming session.

Flatpak requires the runner profile above to allow unprivileged user namespaces.
That keeps `/usr/bin/bwrap` non-setuid, which is required by `flatpak-spawn --share-pids` for Proton/UMU launchers such as Heroic. To verify the runtime profile from a terminal in the container:

```bash
stat -c '%A %U:%G %a' /usr/bin/bwrap
unshare -Ur true
bwrap --ro-bind / / --proc /proc --dev /dev /usr/bin/true
```

## Configuration

| Variable                             | Default                                     | Description                                                   |
| ------------------------------------ | ------------------------------------------- | ------------------------------------------------------------- |
| `STEAMOS_SESSION`                    | `gamescope`                                 | Initial session: `gamescope` or `plasma`                      |
| `GAMESCOPE_FORCE_WINDOWS_FULLSCREEN` | `off`                                       | `on` adds gamescope's `--force-windows-fullscreen` workaround |
| `STEAM_STARTUP_FLAGS`                | `-gamepadui -steamos3 -steampal -steamdeck` | Flags passed to Steam                                         |

Shared variables such as `PUID`, `PGID`, `GOW_DEBUG`, and `GAMESCOPE_*` are documented in [common runtime](../../docs/common-runtime.md).

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

On first boot, the image detects the old upstream GoW layout and migrates it. The two images should not share the same data directory after migration. Use separate Wolf profiles if you need to switch between them.

## Updates

Steam itself updates through Steam. Decky Loader pins are tracked in `build/pins.env` and updated by this image's update scripts.
