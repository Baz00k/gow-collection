# Drop App

[Drop](https://github.com/Drop-OSS/drop) desktop client packaged for Games on Whales / Wolf.

> [!WARNING]
> Drop is in maintenance mode upstream: maintainers are not adding new large features, but bugs are still being fixed and external contributions are merged. This image tracks those releases.

The desktop client used to live in its own [Drop-OSS/drop-app](https://github.com/Drop-OSS/drop-app) repository, which is archived. Releases are now published from the [Drop-OSS/drop](https://github.com/Drop-OSS/drop) monorepo.

## Quick Start

```toml
[[profiles.apps]]
title = "Drop"
icon_png_path = "https://raw.githubusercontent.com/Drop-OSS/drop/develop/desktop/src-tauri/icons/128x128.png"
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
    "CapAdd": ["SYS_NICE", "NET_RAW", "MKNOD", "NET_ADMIN"],
    "Privileged": false,
    "DeviceCgroupRules": ["c 13:* rwm", "c 244:* rwm"]
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

The image bundles [`umu-run`](https://github.com/Open-Wine-Components/umu-launcher), which the client uses to launch Windows games. Proton builds are not bundled; drop each one into `/usr/share/steam/compatibilitytools.d/` (needs its `proton` binary and a `compatibilitytool.vdf` file) and Drop picks it up automatically.

## Troubleshooting

See [shared troubleshooting](../../docs/troubleshooting.md) first. Drop-specific startup failures are usually missing `DROP_SERVER_URL`, browser/auth problems, or open-file limits during downloads.
