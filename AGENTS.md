# AGENTS.md

Docker image collection for [Games on Whales](https://github.com/games-on-whales/gow) / [Wolf](https://github.com/games-on-whales/wolf). No application source — only Dockerfiles, bash scripts, and GitHub Actions. The code is the source of truth; read it before changing it.

## Layout

```
images/<name>/
├── build/        # Dockerfile, pins.env, overlay/ (copied to / in the image), .dockerignore
├── tests/        # run-smoke.sh orchestrator + smoke-*.sh
├── update/       # optional: check.sh + apply.sh for automated dependency bumps
└── README.md

tests/policy-check.sh    # repo-wide policy checks (no Docker needed)
.github/                 # CI; auto-discovers images via images/*/build/pins.env
docs/                    # common-runtime.md, troubleshooting.md
```

## Base image

`images/base/` is a Fedora-based image providing the shared runtime contract (runtime user + `gosu` handoff, `/etc/cont-init.d/*` runner, NVIDIA/device init, setuid bubblewrap for Flatpak sandboxing). It owns the `ENTRYPOINT` (`/opt/gow/entrypoint.sh`). App images `FROM ${BASE_APP_IMAGE}` and only add packages + an overlay `startup.sh`.

Pinning:
- Base pins upstream Fedora by rolling tag **and** digest (`BASE_IMAGE` + `BASE_IMAGE_DIGEST`) because the Fedora registry garbage-collects old digests.
- App images pin the base by digest on our GHCR (which retains digests), so the pin never rots.

Ownership is split: `images/base/update/*` owns only base dependencies; each app's `update/*` owns only app dependencies and must never touch `BASE_APP_IMAGE`. Base-digest propagation across the repo is handled by `.github/scripts/propagate-base-digest.sh` from `update.yml`.

## Commands

```bash
# Policy checks (all images, or one)
./tests/policy-check.sh
./tests/policy-check.sh images/drop-app

# Build one image
docker build \
  --build-arg BASE_APP_IMAGE="$(grep BASE_APP_IMAGE images/<name>/build/pins.env | cut -d= -f2)" \
  -t gow-collection/<name>:test images/<name>/build/

# Smoke tests (needs the built image)
IMAGE_NAME="gow-collection/<name>:test" images/<name>/tests/run-smoke.sh

# Update scripts
GITHUB_OUTPUT=/dev/null bash images/<name>/update/check.sh
GITHUB_OUTPUT=/dev/null bash images/<name>/update/apply.sh
```

Smoke evidence goes to `test-results/<name>/` (gitignored).

## Conventions

- **Bash**: `set -euo pipefail`; double-quote variables; `UPPER_SNAKE` vars, `lower_snake` functions, `kebab-case` files; smoke tests prefixed `smoke-`. Shebang `#!/bin/bash` (update scripts use `#!/usr/bin/env bash`).
- **Dockerfiles**: start `# syntax=docker/dockerfile:1.4`; app images declare `ARG BASE_APP_IMAGE` and use exactly one `FROM ${BASE_APP_IMAGE}` (no direct upstream `FROM`); Fedora uses `dnf` (`dnf clean all && rm -rf /var/cache/dnf`); verify downloads with `sha256sum -c`; copy the overlay with `COPY --chmod=755 overlay /`; set `ENV XDG_RUNTIME_DIR=/tmp/.X11-unix`; end with OCI labels.
- **pins.env**: `BASE_APP_IMAGE` must pin `ghcr.io/<owner>/gow-collection/base:edge@sha256:<digest>`; app versions get a matching `*_SHA256`.
- **Update scripts**: communicate via `$GITHUB_OUTPUT` (`check.sh` → `update_available`, `apply.sh` → `applied`, both optionally `summary_md`); receive `PINS_FILE` and `IMAGE_DIR`; must be executable.

These are enforced by `tests/policy-check.sh` (digest pinning, single base `FROM`, no placeholder digests, verified downloads, no committed secrets). Run it before assuming a change is correct.

## Adding an image

Create `build/` (Dockerfile, pins.env, overlay/, .dockerignore), `tests/` (run-smoke.sh + smoke-*.sh), `README.md`, and optionally `update/`. No workflow changes — CI discovers images via `images/*/build/pins.env`. See [CONTRIBUTING.md](CONTRIBUTING.md).
