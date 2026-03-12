# Steam on GoW

Fedora 43-based Steam container optimized for [Wolf](https://github.com/games-on-whales/wolf) streaming. Delivers console-like gaming via gamescope with performance tuning and SteamOS compatibility.

## Quick Start

```toml
[apps.steam]
title = "Steam"
start_virtual_compositor = true

[apps.steam.runner]
type = "docker"
name = "steam"
image = "ghcr.io/Baz00k/gow-collection/steam:edge"
```

## Key Features

- **Gamescope compositor** — frame pacing, scaling, reduced input latency
- **MangoHud overlay** — real-time FPS, GPU/CPU stats
- **GameMode** — automatic CPU governor and I/O tuning
- **Two Steam modes** — Standard Big Picture (`GAMESCOPE_STEAM_MODE=off`, default) or SteamOS GamepadUI (`GAMESCOPE_STEAM_MODE=on`)
- **Decky Loader** — SteamOS plugin framework
- **Automatic Restart** — Steam automatically restarts after updates (configurable via `GOW_RESTART_*` environment variables)

## Documentation

| Document                                   | Contents                                                   |
| ------------------------------------------ | ---------------------------------------------------------- |
| [Configuration](docs/configuration.md)     | Environment variables, Wolf setup, tags                    |
| [Features](docs/features.md)               | Detailed feature list, mode comparison, MangoHud shortcuts |
| [Quirks & Troubleshooting](docs/quirks.md) | Known limitations, workarounds, common issues              |

## Differences from Upstream GoW Steam

This image uses Valve's standard data layout (`~/.steam/steam` → `~/.local/share/Steam/`). On first boot, it automatically migrates data from the upstream Ubuntu-based image. The two images cannot share the same data directory — migrate the data or use separate Wolf profiles.

## Tags

- `edge` — latest main branch
- `vX.Y.Z` — release versions
- `sha-abc1234` — commit-pinned

## Updates

Dependency updates are detected weekly and proposed as PRs automatically.
