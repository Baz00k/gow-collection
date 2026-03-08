# drop-app on GoW

Docker image for running [Drop](https://github.com/Drop-OSS/drop-app) on [Games on Whales](https://github.com/games-on-whales/gow) (`base-app:edge`).

## Usage

```bash
docker pull ghcr.io/Baz00k/gow-collection/drop-app:edge
```

## Configuration

| Variable           | Description                    |
| ------------------ | ------------------------------ |
| `DROP_SERVER_URL`  | Your Drop server URL           |
| `PUID` / `PGID`    | User/group IDs (default: 1000) |
| `RUN_GAMESCOPE`    | Use gamescope compositor       |
| `GAMESCOPE_WIDTH`  | Display width (default: 1920)  |
| `GAMESCOPE_HEIGHT` | Display height (default: 1080) |

## Wolf

Example `apps.toml` entry:

```toml
[apps.drop]
title = "Drop"
icon_png_path = "https://raw.githubusercontent.com/Drop-OSS/drop-app/develop/src-tauri/icons/icon.png"
start_virtual_compositor = true

[apps.drop.runner]
type = "docker"
name = "drop-app"
image = "ghcr.io/Baz00k/gow-collection/drop-app:edge"
env = ["DROP_SERVER_URL=https://your-server.example.com"]
```

## Tags

- `edge` — latest main branch build
- `vX.Y.Z` — release versions
- `sha-abc1234` — commit-pinned

## Updates

Upstream dependency updates (base image, drop-app releases) are detected weekly and proposed as PRs automatically.

## Windows Games (Proton)

Drop's `develop` branch has built-in [Proton/UMU support](https://github.com/Drop-OSS/drop-app/blob/develop/src-tauri/process/src/compat.rs) for running Windows games on Linux, but this is not yet included in the latest release (v0.3.4). Once a new version ships with compatibility layer support, this image will be updated to bundle `umu-run` and Proton.

## Troubleshooting

### "Too many open files" during downloads

Games with many files can hit the container's open-file limit ([Drop-OSS/drop-app#127](https://github.com/Drop-OSS/drop-app/issues/127)). The startup script raises this automatically, but if you still see the error, pass the limit explicitly:

```toml
[apps.drop.runner]
ulimits = ["nofile=65536:65536"]
```

## Rollback

```bash
docker pull ghcr.io/Baz00k/gow-collection/drop-app@sha256:<digest>
```
