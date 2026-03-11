# Quirks & Troubleshooting

## Known Limitations

### Desktop Mode Menu Bar

In desktop mode (after exiting Big Picture), the top menu bar dropdowns don't open:

- Steam, View, Friends, Games, Help menus are unresponsive
- This is a gamescope limitation—it's designed for fullscreen gaming, not CEF popups

**Workarounds:**

- Use Big Picture settings (gear icon) for most configuration
- Use Steam URL commands from a terminal: `steam steam://settings`
- Navigate directly to settings pages in the web UI

### SteamOS Mode "Switch to Desktop"

In `GAMESCOPE_STEAM_MODE=on`, the "Switch to desktop" button doesn't work:

- There's no underlying desktop session to switch to
- The button is designed for Steam Deck's dual-mode OS

**Workaround:** Use standard mode (`GAMESCOPE_STEAM_MODE=off`) if you need desktop access.

### Data Directory Incompatibility

This image cannot share data directories with the upstream GoW Steam image:

- Upstream stores data in `~/.steam/steam/` (real directory)
- This image uses `~/.steam/steam` → `~/.local/share/Steam/` (symlink)
- Upstream would recreate the directory on start, breaking the symlink

**Solution:** Use separate Wolf profile data directories for each image.

## Migration from Upstream GoW

If switching from `ghcr.io/games-on-whales/gow` Steam image:

1. On first boot, this image detects the old layout automatically
2. Copies `~/.steam/steam/` contents to `~/.local/share/Steam/`
3. Replaces the directory with a symlink

**To roll back:** Restore from backup—the symlink won't work with upstream.

## Troubleshooting

### Games crash on startup

Some games require higher memory map limits. Add to your Wolf config:

```toml
[apps.steam.runner]
sysctls = ["vm.max_map_count=1048576"]
```

Affected games: The Finals, Hogwarts Legacy, DayZ, CS2.

### GPU not detected (NVIDIA)

This image doesn't bundle NVIDIA drivers. Ensure your host has:

- NVIDIA drivers installed
- `nvidia-container-toolkit` configured

### gamescope fails to start

Ensure `XDG_RUNTIME_DIR` is set. The entrypoint creates `/tmp/.X11-unix` automatically.

### MangoHud not visible

- In standard mode: MangoHud starts hidden. Press `Right Shift + F12` to toggle it on.
- In SteamOS mode: Steam controls MangoApp visibility. Use `Right Shift + F12` to force-show, or change the performance overlay level in Steam settings.

### MangoHud Frozen Stats in SteamOS Mode

In `GAMESCOPE_STEAM_MODE=on`, MangoApp may display frozen or inaccurate FPS values (e.g., showing 6 FPS while the game runs at 100+ FPS). Hardware stats (GPU/CPU temps) can also freeze periodically.

This is a known gamescope limitation with nested Wayland compositors. MangoApp receives frametime data from gamescope via IPC message queue, and the `--backend wayland` path (required for Wolf) doesn't always pump frames to the IPC reliably. The same class of issue affects Hyprland users upstream ([gamescope#1431](https://github.com/ValveSoftware/gamescope/issues/1431)).

**This does not affect game performance** — only the overlay display is wrong.

**Workaround:** Use standard Big Picture mode (`GAMESCOPE_STEAM_MODE=off`) where MangoHud injects directly into games via the Vulkan layer and shows accurate stats.

### Container exits immediately

Check Steam isn't already running with the same data directory. Steam uses file locks that prevent multiple instances.

## Rollback

Pull a specific digest to rollback:

```bash
docker pull ghcr.io/Baz00k/gow-collection/steam@sha256:<digest>
```

Find digests in the [GitHub Container Registry](https://github.com/Baz00k/gow-collection/pkgs/container/gow-collection%2Fsteam).
