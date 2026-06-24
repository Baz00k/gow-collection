# Drop App

[Drop](https://github.com/Drop-OSS/drop-app) desktop client packaged for Games on Whales / Wolf.

## Quick Start

```toml
[[profiles.apps]]
title = "Drop"
icon_png_path = "https://raw.githubusercontent.com/Drop-OSS/drop-app/main/app-icon.png"
start_virtual_compositor = true

[profiles.apps.runner]
type = "docker"
name = "WolfDrop"
image = "ghcr.io/Baz00k/gow-collection/drop-app:edge"
mounts = []
env = [
    "DROP_SERVER_URL=https://your-server.example.com"
]
devices = []
ports = []
base_create_json = """
{
  "HostConfig": {
    "IpcMode": "host",
    "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN"],
    "Privileged": false,
    "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
  }
}
\
"""
```

## App-Specific Configuration

| Variable          | Required | Description                                                         |
| ----------------- | -------- | ------------------------------------------------------------------- |
| `DROP_SERVER_URL` | Usually  | URL of your Drop server                                             |
| `BROWSER`         | No       | Browser used by Drop for auth/external links. Defaults to `firefox` |

Common variables such as `PUID`, `PGID`, `GOW_DEBUG`, and `GAMESCOPE_*` are documented in [common runtime](../../docs/common-runtime.md).

## Notes

If you hit open-file limits, set the limit explicitly in Wolf:

```toml
[profiles.apps.runner]
ulimits = ["nofile=65536:65536"]
```

## Windows Games

Drop's `develop` branch has built-in [Proton/UMU support](https://github.com/Drop-OSS/drop-app/blob/develop/src-tauri/process/src/compat.rs), but this is not yet included in the latest release used here. When a release ships compatibility-layer support, this image can add `umu-run` and Proton.

## Updates

The Drop release URL and checksum are tracked in `build/pins.env` and updated by this image's update scripts.

## Troubleshooting

See [shared troubleshooting](../../docs/troubleshooting.md) first. Drop-specific startup failures are usually missing `DROP_SERVER_URL`, browser/auth problems, or open-file limits during downloads.
