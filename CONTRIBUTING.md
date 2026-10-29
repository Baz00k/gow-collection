# Contributing

Everything for an image lives in `images/<name>/`. CI discovers images by `images/*/build/pins.env`, so adding one never touches workflow files. Copy an existing image as a starting point.

## Adding an image

- `build/`: `Dockerfile`, `pins.env`, `.dockerignore`, and `overlay/` (copied to `/`; at minimum `opt/gow/startup.sh`).
- `tests/`: `run-smoke.sh`, which runs every `smoke-*.sh`.
- `update/` (optional): `check.sh` and `apply.sh`.
- `README.md`: only what is specific to this image, plus a Wolf `[[profiles.apps]]` example. Shared runtime and troubleshooting belong in `docs/`.

## pins.env

Every key becomes a Docker build-arg. `BASE_APP_IMAGE` pins the base by digest; each downloaded artifact gets a `*_SHA256` that the Dockerfile checks with `sha256sum -c`.

```bash
BASE_APP_IMAGE=ghcr.io/<owner>/gow-collection/base:edge@sha256:<digest>
APP_VERSION=1.2.3
APP_SHA256=<sha256-of-artifact>
```

## Update scripts

`update.yml` runs `check.sh`, then `apply.sh` if an update is available, passing `PINS_FILE`, `IMAGE_DIR`, and `GITHUB_OUTPUT`. Both must be executable and write to `$GITHUB_OUTPUT`:

- `check.sh`: `update_available=true|false`
- `apply.sh`: `applied=true|false`, plus an optional `summary_md<<EOF … EOF` block for the PR body

Update only your image's pins; `BASE_APP_IMAGE` is bumped repo-wide by `.github/scripts/propagate-base-digest.sh`.

Try them locally with `GITHUB_OUTPUT=/dev/null bash images/<name>/update/check.sh`.

## Before opening a PR

`./tests/policy-check.sh` and the image's `tests/run-smoke.sh` both pass.
