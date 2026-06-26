# Common Runtime

These settings work the same way for every image in this repository.

## User And Files

Containers run the app as a normal user, not as root.

| Variable | Default       | Description                                 |
| -------- | ------------- | ------------------------------------------- |
| `PUID`   | `1000`        | UID used for files written by the container |
| `PGID`   | `1000`        | GID used for files written by the container |
| `UNAME`  | `retro`       | Username inside the container               |
| `UHOME`  | `/home/retro` | Home directory inside the container         |

If you mount a host directory, set `PUID` and `PGID` to the host user that owns that directory.

```toml
env = [
    "PUID=1000",
    "PGID=1000"
]
```

## Debug Logs

Use `GOW_DEBUG` when a container exits early or something is missing from startup logs.

| Value               | Behavior            |
| ------------------- | ------------------- |
| `0`, `false`, `off` | Normal logs         |
| `1`, `true`, `on`   | Debug diagnostics   |
| `2`                 | More verbose probes |
| `3`                 | Shell tracing       |

Use `GOW_DEBUG=3` only in trusted environments because shell traces can expose environment values.

## Gamescope Sessions

Most GUI images launch through gamescope. Configure resolution here:

| Variable                | Default        | Description                          |
| ----------------------- | -------------- | ------------------------------------ |
| `GAMESCOPE_WIDTH`       | `1920`         | Output width                         |
| `GAMESCOPE_HEIGHT`      | `1080`         | Output height                        |
| `GAMESCOPE_GAME_WIDTH`  | same as width  | Game width                           |
| `GAMESCOPE_GAME_HEIGHT` | same as height | Game height                          |
| `GAMESCOPE_REFRESH`     | `60`           | Refresh rate                         |
| `GAMESCOPE_MODE`        | `-b`           | Gamescope mode, such as `-b` or `-f` |
| `GAMESCOPE_EXTRA_ARGS`  | empty          | Extra gamescope arguments            |

## Host Game Setting

Some games need a higher memory map limit. If a game crashes on launch, set this on the host:

```bash
sudo sysctl -w vm.max_map_count=1048576
echo "vm.max_map_count=1048576" | sudo tee /etc/sysctl.d/99-gaming.conf
sudo sysctl --system
```

## AppImages And FUSE

The images include FUSE 2 and FUSE 3 userspace support so AppImages can mount
their embedded filesystem at runtime. The host runner must also pass through the
FUSE device:

```toml
devices = ["/dev/fuse"]
```

Some FUSE workloads may also require relaxed security options such as
`SYS_ADMIN`, `seccomp=unconfined`, or `apparmor=unconfined`, depending on the
runner profile and the filesystem being mounted.

## Image Tags

| Tag            | Meaning                             |
| -------------- | ----------------------------------- |
| `edge`         | Latest successful build from `main` |
| `sha-<commit>` | Image built from a specific commit  |
| `vX.Y.Z`       | Release tags, when published        |

For rollback, pull a specific digest from GHCR:

```bash
docker pull ghcr.io/Baz00k/gow-collection/<image>@sha256:<digest>
```
