# Eden

[Eden](https://git.eden-emu.dev/eden-emu/eden) Nintendo Switch emulator for Games on Whales / Wolf, launched through gamescope.

## Configuration

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
    "/srv/eden/keys:/keys:ro"
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
    "CapAdd": ["SYS_NICE", "NET_RAW", "MKNOD", "NET_ADMIN"],
    "Privileged": false,
    "DeviceCgroupRules": ["c 13:* rwm", "c 244:* rwm"]
  }
}
\
"""
```

Shared variables (`PUID`, `GOW_DEBUG`, `GAMESCOPE_*`) are in [common runtime](../../docs/common-runtime.md).

## Files you supply

Keys, firmware, and games come from your own hardware. See [LEGAL.md](LEGAL.md).

| What | How |
| --- | --- |
| Keys | Put `prod.keys` and `title.keys` in the host directory mounted at `/keys`. At startup every `*.keys` file in `EDEN_KEYS_DIR` (default `/keys`) is copied to `~/.local/share/eden/keys`, unless a file of that name is already there. |
| Firmware | Mount the dump read-only and install it from Eden's own UI. |
| Games | Mount the dumps read-only and add the mount path as a game directory in Eden. |

Mount `/keys` outside the profile home: the base image chowns the home at startup, and a read-only mount below it breaks init. To update a key, delete the copied file in the profile first.

## Persistence

Wolf mounts a per-profile home at `/home/retro`, which is enough. Eden writes to two places there.

| Path | Contents |
| --- | --- |
| `~/.config/eden` | Settings |
| `~/.local/share/eden` | Keys, NAND, saves, firmware, shader cache |

## Hardware

The pinned build is upstream's generic amd64 PGO AppImage, which requires a Haswell- or Ryzen-class CPU or newer. For older CPUs, point `EDEN_APPIMAGE_URL` and `EDEN_APPIMAGE_SHA256` in `build/pins.env` at the release's `legacy-clang-pgo` asset and rebuild.

Eden uses its bundled Mesa drivers. On NVIDIA hosts the startup script enables the host driver's Vulkan ICD when `/usr/share/vulkan/icd.d/nvidia_icd.json` exists. Eden needs Vulkan 1.1-level device features, so any current driver works.

Upstream's AppRun forces X11 inside gamescope. Set `I_WANT_A_BROKEN_WAYLAND_UI=1` to use Wayland instead.
