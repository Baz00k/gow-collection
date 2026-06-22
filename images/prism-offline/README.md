# Prism Launcher Offline

Offline-capable Prism Launcher image for Games on Whales / Wolf.

## Quick Start

```toml
[[profiles.apps]]
title = "Prism Launcher"
icon_png_path = "https://raw.githubusercontent.com/PrismLauncher/PrismLauncher/develop/program_info/org.prismlauncher.PrismLauncher.png"
start_virtual_compositor = true

[profiles.apps.runner]
type = "docker"
name = "WolfPrismLauncher"
image = "ghcr.io/Baz00k/gow-collection/prism-offline:edge"
mounts = []
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
    "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
  }
}
\
"""
```

## What Is Included

- Offline-capable Prism Launcher fork from [Diegiwg/PrismLauncher-Cracked](https://github.com/Diegiwg/PrismLauncher-Cracked).
- Bundled Temurin JREs for Minecraft version coverage:
    - Java 21 for Minecraft 1.21+.
    - Java 17 for Minecraft 1.18 through 1.20.4.
    - Java 8 for Minecraft 1.16 and older.
- No Minecraft game assets or accounts.

## Legal And Account Policy

Read [LEGAL.md](LEGAL.md) before using this image.

- Users must own a legitimate Minecraft license for gameplay.
- Offline profiles are for local/LAN play or `online-mode=false` servers.
- This project does not bypass Mojang/Microsoft authentication.
- Certain launchers are prohibited due to security concerns documented in `LEGAL.md`.

## App-Specific Configuration

There are no required image-specific environment variables.

Common variables such as `PUID`, `PGID`, and `GOW_DEBUG` are documented in [common runtime](../../docs/common-runtime.md).

## Updates

Prism AppImage URLs/checksums and Temurin JRE URLs/checksums are tracked in `build/pins.env`.

## Troubleshooting

See [shared troubleshooting](../../docs/troubleshooting.md) first. Prism-specific problems are usually launcher/profile/account configuration or missing Minecraft assets downloaded by the launcher at runtime.
