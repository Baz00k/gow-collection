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

Some games require a higher memory map limit:

```bash
sudo sysctl -w vm.max_map_count=1048576
echo "vm.max_map_count=1048576" | sudo tee /etc/sysctl.d/99-gaming.conf
sudo sysctl --system
```

The container tries to set this automatically when it has enough privilege, but setting it on the host is the most reliable option.

## Container Exits Immediately

Check the app logs first. Common causes are:

- The application exited normally.
- Another instance is already using the same data directory.
- A required display socket or GPU device is missing.
- A required app-specific environment variable is missing.

## Image Does Not Pull

Check GHCR availability and the package page for the image you are trying to pull.
