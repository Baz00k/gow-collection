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
| MangoHud overlay | Visible by default | Hidden initially (Steam-controlled) |
| MangoApp integration | No | Yes (horizontal bar) |
| Variable Rate Shading | Not available | Enabled |
| Gamescope scaling | Not available | Enabled |
| Desktop mode switch | Available | Not available |

```toml
[apps.steam.runner]
env = ["GAMESCOPE_STEAM_MODE=on"]
```

### Container Lifecycle

The container runs for as long as Steam is running. When Steam exits (whether via "Exit Steam" from desktop mode or closing the window), the container stops and the Wolf session ends.

**With `GAMESCOPE_STEAM_MODE=off` (default):**
- Steam starts in Big Picture mode
- Clicking **"Exit Big Picture"** switches to **desktop mode** — Steam keeps running, you can manage your library
- Clicking **"Exit Steam"** (or closing the window) from desktop mode ends the container

**With `GAMESCOPE_STEAM_MODE=on`:**
- Steam enters SteamOS/GamepadUI mode
- The **"Switch to desktop"** button attempts to switch modes but may not work as expected in a containerized environment with no underlying desktop session
- **Power Off / Restart / Suspend** menu items will trigger Steam to exit, ending the container (these are intercepted to prevent actual host shutdown)

For the most predictable behavior when you need to manage your library (add external games, change settings), use the default mode (`off`) and switch to desktop mode from Big Picture.

### Desktop Mode Limitations

After exiting Big Picture, Steam switches to its desktop mode UI. This works for browsing your library, store, and community pages, but the **top menu bar dropdowns (Steam, View, Friends, Games, Help) do not open** when clicked. This is a known architectural limitation of gamescope — it is designed for fullscreen gaming and does not fully support the popup windows that Steam's CEF-based desktop UI creates for dropdown menus.

**Workarounds for accessing settings:**

- Use Big Picture mode: settings are accessible via the gear icon in Big Picture
- Use Steam URL shortcuts from a terminal inside the container: `steam steam://settings`
- Navigate to settings pages directly in the Steam client's web-based UI (Store, Library, etc. all work normally)

## Features

- **Gamescope compositor** — Valve's gaming-focused display server for frame pacing and scaling
- **MangoHud overlay** — Real-time FPS, GPU/CPU stats, and frame time graph (visible by default in both modes)
- **GameMode optimization** — On-demand CPU governor and I/O priority tuning
- **UMU-Launcher/Proton support** — Unified Proton launcher for Windows games
- **Decky Loader plugin framework** — SteamOS plugin system for customizations
- **SteamOS compatibility stubs** — `steamos-update`, `steamos-session-select`, and related helpers
- **Container-safe performance tuning** — `vm.max_map_count` and scheduler tweaks where permitted

### MangoHud Keyboard Shortcuts

The overlay is visible by default. Use these shortcuts to control it:

| Shortcut | Function |
|----------|----------|
| `Right Shift + F12` | Toggle overlay on/off |
| `Right Shift + F11` | Change overlay position (corners/center) |
| `Right Shift + F10` | Toggle preset (change verbosity) |

**Note:** In `GAMESCOPE_STEAM_MODE=on`, the overlay starts hidden (`no_display`) and Steam controls visibility via gamescope integration. Use the shortcuts above to show/hide it manually.

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
