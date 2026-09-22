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

## How It Works

At startup the container:

1. Starts the system D-Bus daemon and Avahi (mDNS publishing) via cont-init.
2. Generates `~/.config/wivrn/config.json` from `WIVRN_*` variables.
3. Starts PipeWire + WirePlumber and points `PULSE_SERVER` at PipeWire,
   replacing Wolf's PulseAudio inside this container.
4. Starts `wivrn-server` and waits for it to listen.
5. Exports `PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1` so Steam's
   Pressure Vessel container picks up the host OpenXR runtime.
6. Launches Steam inside gamescope.

## Configuration

| Variable               | Default    | Description                                                            |
| ---------------------- | ---------- | ---------------------------------------------------------------------- |
| `WIVRN_ENCODER`        | `auto`     | `auto`, `vulkan`, `nvenc`, `vaapi`, or `x264`                          |
| `WIVRN_CODEC`          | empty      | `h264`, `h265`, `av1`, or `raw` (combined with the encoder)            |
| `WIVRN_TCP_ONLY`       | `false`    | `true` disables UDP (higher latency, useful for WAN/VPN)               |
| `WIVRN_PUBLISH`        | `avahi`    | `avahi` publishes over mDNS; `off` requires manual address entry       |
| `WIVRN_PORT`           | `9757`     | TCP/UDP port the headset connects to                                   |
| `WIVRN_APPLICATION`    | empty      | App started on headset connect, e.g. `["steam", "steam://launch/..."]` |
| `STEAM_STARTUP_FLAGS`  | empty      | Flags passed to Steam (plain Steam, no GamepadUI by default)           |
| `VR_OVERRIDE`          | OpenComposite path | OpenVR compatibility runtime for SteamVR games              |

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
- Steam itself updates through Steam. The image can be updated through the Wolf UI or CLI.

## Updates

The WiVRn server is built from the pinned upstream release in `build/pins.env`
(`WIVRN_VERSION`), because the Quest client and the server versions must match
and Fedora lags upstream. `update/check.sh` + `update/apply.sh` track new
upstream releases automatically through `update.yml`. Steam itself updates
through Steam. The image can be updated through the Wolf UI or CLI.
