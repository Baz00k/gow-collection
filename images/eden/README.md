# Eden

[Eden](https://git.eden-emu.dev/eden-emu/eden) Nintendo Switch emulator for Games on Whales / Wolf, running in a gamescope session.

## Quick Start

```toml
[[profiles.apps]]
title = "Eden"
start_virtual_compositor = true

[profiles.apps.runner]
type = "docker"
name = "WolfEden"
image = "ghcr.io/baz00k/gow-collection/eden:edge"
mounts = [
    "/srv/games/switch:/games:ro",
    "/srv/eden/keys:/home/retro/.local/share/eden/keys:ro"
]
env = [
    "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
]
devices = []
ports = []
base_create_json = """
{
  "HostConfig": {
    "IpcMode": "host",
    "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN"],
    "Privileged": false,
    "DeviceCgroupRules": ["c 13:* rwm", "c 244:* rwm"]
  }
}
\
"""
```

Adjust the mount paths to your host layout. Wolf mounts each profile/app home at `/home/retro`, so no extra volume is needed for Eden's own data.

## What Is Included

- Upstream stable Linux `amd64` PGO AppImage (version pinned in `build/pins.env`).
- The AppImage is **unpacked at build time** and the extracted tree is executed directly, so the container needs no `/dev/fuse` and no extra capabilities.
- The bundle carries its own Qt, Vulkan loader, Mesa drivers, FFmpeg, SDL, and PulseAudio/ALSA client libraries.
- No firmware, encryption keys, or game dumps.

## First Run

Eden starts with an empty configuration. Three things are needed before games launch:

1. **Keys.** Dump `prod.keys` and `title.keys` from your own console and put them on the host, then mount that directory over `/home/retro/.local/share/eden/keys` as in the snippet above. If Eden needs to write into that directory, drop the `:ro` flag or copy the files into the profile volume instead.
2. **Firmware.** Dump the console firmware to a host directory, mount it read-only, and run Eden's firmware installer from the `File` menu, pointing it at the mounted dump.
3. **Games.** Add the game directory (for example `/games`) under `File` → `Add Game Directory`. Mount dumps read-only: the emulator only needs read access.

## Storage

Wolf gives each profile and app its own home directory at `/home/retro`, and Eden keeps everything under it:

| Path                     | Contents                                            |
| ------------------------ | --------------------------------------------------- |
| `~/.config/eden`         | Emulator settings and per-game configuration         |
| `~/.local/share/eden`    | Keys, NAND, saves, installed firmware, shader cache  |

Keep game dumps and firmware dumps on host mounts rather than in the profile directory; they are large and read-only.

## Graphics

- **Drivers.** The bundled Mesa stack is used by default. On NVIDIA hosts the base image publishes the mounted host driver's ICD and the startup script enables system Vulkan ICDs automatically, so no configuration is needed.
- **Vulkan version.** Eden 0.2.x requires Vulkan 1.4.321 or newer. Use a reasonably current host driver.
- **CPU target.** This image ships upstream's generic `amd64` build, which needs Haswell/Ryzen or newer. For older CPUs, point `EDEN_APPIMAGE_URL` / `EDEN_APPIMAGE_SHA256` in `build/pins.env` at the `legacy-clang-pgo` asset from the same release and rebuild. The `steamdeck` and `rog-ally` assets are tuned for specific CPUs and are not a good default for arbitrary servers.
- **Wayland.** Upstream's AppRun hook forces X11 inside gamescope because Eden has known Wayland issues. Set `I_WANT_A_BROKEN_WAYLAND_UI=1` if you want to try the Wayland path anyway.

## Audio

Audio goes through the PulseAudio server Wolf provides; the bundled `libpulse`/`libasound` client libraries pick it up from the environment. No image-specific audio configuration exists.

## Performance

Large shader caches and JIT mappings can exceed the host's default memory map limit. See [common runtime](../../docs/common-runtime.md) for `vm.max_map_count` and the `GAMESCOPE_*` session settings.

## Updating

`update/check.sh` polls Eden's own Forgejo API for the latest **stable** release and `update/apply.sh` re-pins the AppImage URL and its SHA256 (upstream publishes no checksum files). Nightly builds are not tracked; nightly asset names are stable enough to pin manually if you want them.

## Legal

Read [LEGAL.md](LEGAL.md) before using this image.
