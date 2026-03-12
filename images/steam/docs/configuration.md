# Configuration

## Environment Variables

| Variable               | Default       | Description                                                  |
| ---------------------- | ------------- | ------------------------------------------------------------ |
| `PUID` / `PGID`        | 1000          | User/group IDs for the runtime `retro` user                  |
| `GAMESCOPE_WIDTH`      | 1920          | Display width in pixels                                      |
| `GAMESCOPE_HEIGHT`     | 1080          | Display height in pixels                                     |
| `GAMESCOPE_REFRESH`    | 60            | Refresh rate in Hz                                           |
| `GAMESCOPE_MODE`       | `-b`          | Gamescope window mode (`-b` = borderless, `-f` = fullscreen) |
| `STEAM_STARTUP_FLAGS`  | `-bigpicture` | Flags passed to Steam on startup                             |
| `GAMESCOPE_STEAM_MODE` | `off`         | `on` = SteamOS GamepadUI, `off` = standard Big Picture       |

## Wolf Setup

Minimal `apps.toml` configuration:

```toml
[[profiles.apps]]
title = "Steam"
start_virtual_compositor = true

[profiles.apps.runner]
type = "docker"
name = "steam"
image = "ghcr.io/Baz00k/gow-collection/steam:edge"
```

### With Custom Settings

```toml
[[profiles.apps]]
title = "Steam"
start_virtual_compositor = true

[profiles.apps.runner]
type = "docker"
name = "steam"
image = "ghcr.io/Baz00k/gow-collection/steam:edge"
env = [
    "GAMESCOPE_STEAM_MODE=on",
    "GAMESCOPE_WIDTH=2560",
    "GAMESCOPE_HEIGHT=1440",
    "GAMESCOPE_REFRESH=144"
]
```

### Performance-Critical Games

Some games (The Finals, Hogwarts Legacy, DayZ, CS2) require higher memory map limits. If your Wolf config includes `SYS_ADMIN` in `CapAdd`, the startup script sets `vm.max_map_count=1048576` automatically — no extra configuration needed.

If you prefer not to grant `SYS_ADMIN`, set it on the host:

```bash
# Apply immediately
sudo sysctl -w vm.max_map_count=1048576

# Persist across reboots
echo "vm.max_map_count=1048576" | sudo tee /etc/sysctl.d/99-gaming.conf
sudo sysctl --system
```

## Tags

| Tag           | Description                   |
| ------------- | ----------------------------- |
| `edge`        | Latest build from main branch |
| `vX.Y.Z`      | Semantic version releases     |
| `sha-abc1234` | Specific commit hash          |

## Updates

Upstream dependency updates (Fedora base image, Decky Loader) are detected weekly and proposed as PRs automatically.
