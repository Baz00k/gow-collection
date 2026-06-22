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

## Host Game Setting

Some games need a higher memory map limit. If a game crashes on launch, set this on the host:

```bash
sudo sysctl -w vm.max_map_count=1048576
echo "vm.max_map_count=1048576" | sudo tee /etc/sysctl.d/99-gaming.conf
sudo sysctl --system
```

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
