# Base Image

Shared Fedora base image for the gow-collection. Every other image in this repo builds on top of this image through `BASE_APP_IMAGE` in its `pins.env`.

This is primarily maintainer documentation. User-facing shared behavior is documented in [common runtime](../../docs/common-runtime.md).

## What It Provides

The common Games on Whales runtime contract:

- `/opt/gow/entrypoint.sh` — runtime user creation + `gosu` privilege-drop handoff,
  `/etc/cont-init.d/*` runner, performance tuning. This is the image `ENTRYPOINT`.
- `/opt/gow/logging.sh` — shared colored logging helpers (`log_info`, …).
- `/opt/gow/launch-gamescope.sh` — runs a command inside gamescope.
- `/opt/gow/gamescope-lib.sh` — shared gamescope helpers.
- `/opt/gow/apply-performance-tuning.sh` — best-effort sysctl tuning.
- `/etc/cont-init.d/10-setup-user.sh` — runtime user/group, home, `XDG_RUNTIME_DIR`,
  `/home/deck` symlink, ownership.
- `/etc/cont-init.d/20-setup-devices.sh` — device group access for `/dev/dri`,
  `/dev/nvidia*`, input devices, etc.
- `/etc/cont-init.d/30-nvidia.sh` — NVIDIA driver volume / toolkit integration.
- `/usr/bin/bwrap` — non-setuid bubblewrap for Flatpak sandboxing. Wolf's runner
  profile must allow unprivileged user namespaces; Flatpak PID-sharing features
  used by Proton/UMU launchers do not work with setuid bwrap.
- FUSE 2/3 userspace — support for AppImages and other user-space filesystem
  tools when the container is allowed to access `/dev/fuse`.
- `/usr/bin/gosu` — privilege-dropping tool.

App images add their own packages, a `startup.sh`, and any app-specific
`cont-init.d` scripts on top. They inherit the `ENTRYPOINT` from this image.

The entrypoint does not force gamescope; images choose their own session in `startup.sh`.

## Why A Rolling Fedora Tag Plus Tracked Digest

`pins.env` keeps the human-facing Fedora tag (`registry.fedoraproject.org/fedora:44`)
as a rolling tag and records the digest it currently resolves to in
`BASE_IMAGE_DIGEST`. The Dockerfile builds `FROM "${BASE_IMAGE}@${BASE_IMAGE_DIGEST}"`.

This is necessary because the upstream Fedora registry garbage-collects old
digests: a digest-only pin cannot be re-pulled once a new Fedora image ships.
Tracking the digest keeps builds reproducible while `update/check.sh` still
detects when the rolling tag moves to a new digest.

Downstream images do **not** have this problem — they pin this base by digest on
**our** GHCR, which retains old digests, so their pins never rot.

## Update Flow

1. `update/check.sh` + `apply.sh` (run by `update.yml`) detect and apply a new
   Fedora digest here.
2. When this image is rebuilt and published on `main`, `ci.yml` fires
   `repository_dispatch: base-digest-published`, which runs `update.yml`'s
   repo-level propagation path. `.github/scripts/propagate-base-digest.sh` then
   bumps every image that pins the published base, opening one auto-merge PR.
   Merging that PR triggers `ci.yml`, which rebuilds the affected app images.
