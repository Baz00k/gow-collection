# Steam on GoW

Fedora 43-based Docker image for running Steam via gamescope on Games on Whales / Wolf. Provides a console-like gaming experience with performance tuning and SteamOS compatibility features.

## Usage

```bash
docker pull ghcr.io/Baz00k/gow-collection/steam:edge
```

## Configuration

| Variable | Description |
|----------|-------------|
| `PUID` / `PGID` | User/group IDs for the runtime `retro` user (default: 1000) |
| `GAMESCOPE_WIDTH` | Display width (default: 1920) |
| `GAMESCOPE_HEIGHT` | Display height (default: 1080) |
| `GAMESCOPE_REFRESH` | Refresh rate (default: 60) |
| `GAMESCOPE_MODE` | Gamescope mode flag (default: `-b` for borderless) |
| `STEAM_STARTUP_FLAGS` | Steam launch flags (default: `-bigpicture`) |
| `GAMESCOPE_STEAM_MODE` | `on` for SteamOS-like experience, `off` for standard Big Picture (default: `off`) |

## Wolf

Example `apps.toml` entry:

```toml
[apps.steam]
title = "Steam"
icon_png_path = "https://upload.wikimedia.org/wikipedia/commons/thumb/8/83/Steam_icon_logo.svg/512px-Steam_icon_logo.svg.png"
start_virtual_compositor = true

[apps.steam.runner]
type = "docker"
name = "steam"
image = "ghcr.io/Baz00k/gow-collection/steam:edge"
```

## Gamescope Steam Mode

By default (`GAMESCOPE_STEAM_MODE=off`), Steam runs in standard Big Picture mode inside gamescope. This provides a normal Steam UI where you can exit Big Picture, switch to desktop mode, and manage your library freely.

Setting `GAMESCOPE_STEAM_MODE=on` enables gamescope's Steam integration (`-e` flag), which makes Steam enter the SteamOS/GamepadUI interface. This provides a console-like experience with MangoApp overlay, Variable Rate Shading, and gamescope-specific scaling — but also enables power management UI (shutdown/restart/suspend) and replaces "Exit Big Picture" with "Switch to desktop".

| Feature | `off` (default) | `on` |
|---------|-----------------|------|
| Steam UI | Standard Big Picture | SteamOS GamepadUI |
| Exit button | "Exit Big Picture" | "Switch to desktop" |
| Power menu | Hidden | Shutdown / Restart / Suspend |
| MangoApp overlay | Not available | Enabled |
| Variable Rate Shading | Not available | Enabled |
| Gamescope scaling | Not available | Enabled |
| Desktop mode switch | Available | Not available |

```toml
[apps.steam.runner]
env = ["GAMESCOPE_STEAM_MODE=on"]
```

## Features

- **Gamescope compositor** — Valve's gaming-focused display server for frame pacing and scaling
- **MangoHud/MangoApp overlay** — Real-time FPS, temps, and performance metrics (MangoApp requires `GAMESCOPE_STEAM_MODE=on`)
- **GameMode optimization** — On-demand CPU governor and I/O priority tuning
- **UMU-Launcher/Proton support** — Unified Proton launcher for Windows games
- **Decky Loader plugin framework** — SteamOS plugin system for customizations
- **SteamOS compatibility stubs** — `steamos-update`, `steamos-session-select`, and related helpers
- **Container-safe performance tuning** — `vm.max_map_count` and scheduler tweaks where permitted

## Tags

- `edge` — latest main branch build
- `vX.Y.Z` — release versions
- `sha-abc1234` — commit-pinned

## Updates

Upstream dependency updates (Fedora base image, Decky Loader, UMU-Launcher) are detected weekly and proposed as PRs automatically.

## Migrating from upstream GoW Steam image

This image uses a different data layout than the upstream `ghcr.io/games-on-whales/gow` Steam image (Ubuntu-based). The upstream image stores Steam data directly in `~/.steam/steam/` as a real directory. This image uses the standard Valve layout where `~/.steam/steam` is a **symlink** pointing to `~/.local/share/Steam/`.

On first boot, the entrypoint automatically detects the old layout and migrates the data:

1. Copies `~/.steam/steam/` contents into `~/.local/share/Steam/`
2. Replaces the directory with a symlink

**The two images cannot share the same data directory.** The upstream image would recreate `~/.steam/steam` as a directory on every start, breaking the symlink. Use separate Wolf profile data directories for each image.

If switching permanently from the upstream image, point this image at your old data directory — the migration runs once automatically. To roll back to the upstream image afterward, you would need to restore the old data from a backup.

## Troubleshooting

### GPU passthrough requirements

This image follows Wolf's runtime model: containers share host GPU drivers via pass-through. The image does NOT bundle NVIDIA drivers. For NVIDIA GPUs, ensure `nvidia-container-toolkit` is installed on the host.

### vm.max_map_count for game crashes

Some games (The Finals, Hogwarts Legacy, DayZ, CS2) require higher memory map limits. If games crash on startup:

```bash
# On the host
sudo sysctl -w vm.max_map_count=1048576
```

Or pass via Docker:

```toml
[apps.steam.runner]
sysctls = ["vm.max_map_count=1048576"]
```

### gamescope fails to start

Ensure `XDG_RUNTIME_DIR` is set in the container environment. The entrypoint creates `/tmp/.X11-unix` automatically, but Wolf should handle this via its runtime configuration. The image runs Steam as the GoW-standard `retro` user and keeps `/home/deck` as a compatibility symlink to that home directory.

## Rollback

```bash
docker pull ghcr.io/Baz00k/gow-collection/steam@sha256:<digest>
```
