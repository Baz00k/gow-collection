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

## Features

- **Gamescope compositor** — Valve's gaming-focused display server for frame pacing and scaling
- **MangoHud/MangoApp overlay** — Real-time FPS, temps, and performance metrics
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
