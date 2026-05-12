# Configuration

## Environment Variables

| Variable                             | Default        | Description                                                                        |
| ------------------------------------ | -------------- | ---------------------------------------------------------------------------------- |
| `PUID` / `PGID`                      | 1000           | User/group IDs for the runtime `retro` user                                        |
| `GAMESCOPE_WIDTH`                    | 1920           | Display width in pixels                                                            |
| `GAMESCOPE_HEIGHT`                   | 1080           | Display height in pixels                                                           |
| `GAMESCOPE_GAME_WIDTH`               | same as width  | Nested game width advertised to launched games                                     |
| `GAMESCOPE_GAME_HEIGHT`              | same as height | Nested game height advertised to launched games                                    |
| `GAMESCOPE_REFRESH`                  | 60             | Refresh rate in Hz                                                                 |
| `GAMESCOPE_MODE`                     | `-b`           | Gamescope window mode (`-b` = borderless, `-f` = fullscreen)                       |
| `GAMESCOPE_FORCE_WINDOWS_FULLSCREEN` | `off`          | `on` adds gamescope's `--force-windows-fullscreen` workaround                      |
| `STEAM_STARTUP_FLAGS`                | `-bigpicture`  | Flags passed to Steam on startup                                                   |
| `GAMESCOPE_STEAM_MODE`               | `off`          | `on` = SteamOS GamepadUI, `off` = standard Big Picture                             |
| `GOW_DEBUG`                          | `0`            | `1` enables redacted diagnostics; `2` adds verbose probes; `3` enables shell trace |

## Wolf Setup

```toml
[[profiles.apps]]
title = "Steam"
start_virtual_compositor = true

[profiles.apps.runner]
type = "docker"
name = "steam"
image = "ghcr.io/Baz00k/gow-collection/steam:edge"
env = [
    "GAMESCOPE_STEAM_MODE=on",
    "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
]
base_create_json = """
{
  "HostConfig": {
    "IpcMode": "host",
    "ShmSize": 8589934592,
    "CapAdd": ["SYS_ADMIN", "SYS_NICE", "SYS_PTRACE", "NET_RAW", "MKNOD", "NET_ADMIN"],
    "SecurityOpt": ["seccomp=unconfined", "apparmor=unconfined"],
    "Ulimits": [
        {"Name":"nofile", "Hard":10240, "Soft":10240},
        {"Name":"memlock", "Hard":-1, "Soft":-1},
        {"Name":"rtprio", "Hard":99, "Soft":99}
    ],
    "Privileged": false,
    "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
  }
}
"""
```

`/dev/input/*` is required for Moonlight/Wolf virtual input devices. If remote
or controller input does not work, run `ls -l /dev/input /dev/uinput` and
`id retro` inside the container. The `retro` user must have group access to the
exposed input nodes. Add `/dev/hidraw*` or `/dev/uinput` only when a specific
host input path requires it.

### Debugging Startup Issues

Keep `GOW_DEBUG` disabled for normal use. When troubleshooting a failing
profile, enable it temporarily:

```toml
env = [
    "GOW_DEBUG=1",
]
```

Debug mode prints redacted diagnostics for startup and exit handling. It does
not print raw `STEAM_STARTUP_FLAGS` values or full process command lines.
Use `GOW_DEBUG=2` for more verbose filesystem and driver probes. `GOW_DEBUG=3`
enables shell tracing and should only be used in trusted environments because
shell traces can expose environment values.

### Performance-Critical Games

Some games (The Finals, Hogwarts Legacy, DayZ, CS2) require higher memory map limits. If your Wolf config includes `SYS_ADMIN` in `CapAdd`, the startup script sets `vm.max_map_count=1048576` automatically — no extra configuration needed.

If you prefer not to grant `SYS_ADMIN`, set it on the host:

```bash
# Apply immediately
sudo sysctl -w vm.max_map_count=1048576

# Persist across reboots
echo "vm.max_map_count=1048576" | sudo tee /etc/sysctl.d/99-gaming.conf
sudo sysctl --system
```

## Tags

| Tag           | Description                   |
| ------------- | ----------------------------- |
| `edge`        | Latest build from main branch |
| `vX.Y.Z`      | Semantic version releases     |
| `sha-abc1234` | Specific commit hash          |

## Updates

Upstream dependency updates (Fedora base image, Decky Loader) are detected weekly and proposed as PRs automatically.
