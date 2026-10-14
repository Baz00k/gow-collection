# WiVRn + Steam

A native WiVRn + Steam image for Games on Whales / Wolf. VR games stream
directly from the container to a standalone headset (WiVRn client app),
bypassing Moonlight. Steam runs in gamescope for installing and launching
VR titles.

## Quick Start

The container needs host networking so the headset can discover it over mDNS
(port 5353/udp) and connect to WiVRn (port 9757 tcp/udp):

```toml
[[profiles.apps]]
title = "WiVRn"
start_virtual_compositor = true

[profiles.apps.runner]
type = "docker"
name = "WolfWiVRn"
image = "ghcr.io/baz00k/gow-collection/wivrn:edge"
mounts = []
env = [
    "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia* /dev/uinput"
]
devices = []
ports = []
base_create_json = """
{
  "HostConfig": {
    "NetworkMode": "host",
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

Without host networking, publish the ports explicitly instead:

```toml
ports = [
    {private_port = 9757, public_port = 9757, type = "tcp"},
    {private_port = 9757, public_port = 9757, type = "udp"},
    {private_port = 5353, public_port = 5353, type = "udp"}
]
```

Then install the WiVRn client app on the headset, connect to the server, and
launch a VR game from Steam.

> **Don't launch SteamVR itself** — WiVRn only provides an OpenXR runtime and
> there is no SteamVR HMD driver, so SteamVR exits immediately. Launch OpenVR
> or OpenXR games directly instead: OpenVR calls are translated to OpenXR by
> xrizer, which WiVRn configures automatically
> (`WIVRN_OPENVR_COMPAT_PATH`).
>
> **No per-game launch options needed.** Upstream WiVRn prints a
> `... %command%` prefix (`PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1` plus
> `VR_OVERRIDE=...`) for Steam games. This container applies the required settings
> globally before `wivrn-server` and Steam start, so every game — including
> launches triggered from the headset — inherits them. If a game starts on
> the virtual screen with no HMD image and no tracking, it fell back to
> desktop mode: check the startup logs for the `VR_OVERRIDE=...` line.

## Configuration

| Variable               | Default    | Description                                                            |
| ---------------------- | ---------- | ---------------------------------------------------------------------- |
| `WIVRN_ENCODER`        | `auto`     | `auto`, `vulkan`, `nvenc`, `vaapi`, or `x264`                          |
| `WIVRN_CODEC`          | empty      | `h264`, `h265`, `av1`, or `raw` (combined with the encoder)            |
| `WIVRN_TCP_ONLY`       | `false`    | `true` disables UDP (higher latency, useful for WAN/VPN)               |
| `WIVRN_PUBLISH`        | `avahi`    | `avahi` publishes over mDNS; `off` requires manual address entry       |
| `WIVRN_PORT`           | `9757`     | TCP/UDP port the headset connects to                                   |
| `WIVRN_APPLICATION`    | empty      | App started on headset connect, e.g. `["steam", "steam://launch/..."]` |
| `WIVRN_OPENVR_COMPAT_PATH` | `/opt/xrizer` | OpenVR compatibility tool dir managed by WiVRn (`auto` = autodetect the packaged xrizer, `off` = don't manage). Must be the directory containing `bin/linux64/vrclient.so` |
| `STEAM_STARTUP_FLAGS`  | empty      | Flags passed to Steam (plain Steam, no GamepadUI by default)           |
| `VR_OVERRIDE`          | auto-derived | Explicit override for the OpenVR runtime path (leave empty; derived from `WIVRN_OPENVR_COMPAT_PATH` and translated for Pressure Vessel) |

Shared variables such as `PUID`, `PGID`, `GOW_DEBUG`, and `GAMESCOPE_*` are documented in [common runtime](../../docs/common-runtime.md).

Invalid `WIVRN_*` values fail fast at startup so typos surface in the logs
instead of as a headset that never finds the server.

## Remote Access (WAN)

Headsets must normally be on the same LAN as the server. For remote play,
either join both ends to the same VPN, or set `WIVRN_TCP_ONLY=true`,
port-forward the TCP port, and enter `wivrn+tcp://host:port` manually on the
headset with `WIVRN_PUBLISH=off`.

## Caveats

- VR audio goes to the headset over WiVRn. Moonlight audio from this container
  is silent because the container replaces Wolf's PulseAudio with PipeWire.
- NVIDIA encoding through WiVRn/Monado is rough upstream; prefer `nvenc`
  explicitly if auto-selection misbehaves, and check the WiVRn logs.
- Avahi publishing needs D-Bus and multicast on the container network, which
  is why host networking is recommended.
- The packaged xrizer runtime is 64-bit only; 32-bit OpenVR games are not
  supported by this image.

## Per-Game Notes

OpenVR games use a pinned [xrizer release][xrizer-release] (the translator
WiVRn's own [Flatpak][wivrn-steam] uses), installed at `/opt/xrizer`. No
per-game launch options are needed; remove any old `VR_OVERRIDE` launch
options or `WIVRN_OPENVR_COMPAT_PATH` overrides that point at another
translator. Versions are pinned in [`build/pins.env`](build/pins.env) and
bumped automatically with the WiVRn pin.

For Half-Life: Alyx, force Proton instead of the native Linux build. If
controllers disappear, try disabling hand tracking in the WiVRn headset app
and wake the physical controllers before connecting.

For translator failures, inspect the first error in
`~/.local/state/xrizer/xrizer.txt` (or `$XDG_STATE_HOME/xrizer/xrizer.txt`).

[xrizer-release]: https://github.com/Supreeeme/xrizer/releases
[wivrn-steam]: https://github.com/WiVRn/WiVRn/blob/v26.9/docs/steamvr.md
