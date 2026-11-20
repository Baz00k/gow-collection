# Troubleshooting

## Enable Startup Diagnostics

Start with:

```text
GOW_DEBUG=1
```

Use `GOW_DEBUG=2` for more detailed probes. Use `GOW_DEBUG=3` only when you are comfortable with shell tracing appearing in logs.

## Permission Problems In `/home/retro`

Set `PUID` and `PGID` to match the host user that owns the mounted data directory.

```toml
env = [
    "PUID=1000",
    "PGID=1000"
]
```

If you changed these after files were already created, fix ownership on the host data directory.

## GPU Or Device Access Problems

Check that the relevant devices are passed into the container:

- AMD/Intel: `/dev/dri/*`
- NVIDIA: `/dev/nvidia*` and host driver libraries mounted by Wolf/NVIDIA tooling
- Controllers/input: `/dev/input/*`

## Games Crash On Startup

Some games need a higher memory map limit. See [performance](performance.md#memory-map-limit).

## Container Exits Immediately

Check the app logs first. Common causes are:

- The application exited normally.
- Another instance is already using the same data directory.
- A required display socket or GPU device is missing.
- A required app-specific environment variable is missing.

## Image Does Not Pull

Check GHCR availability and the package page for the image you are trying to pull.
