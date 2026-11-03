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

`update.yml` runs `check.sh`, then `apply.sh` if an update is available, passing `PINS_FILE`, `IMAGE_DIR`, `GITHUB_OUTPUT`, and `PIN_UPDATES`. Both must be executable:

- `check.sh`: writes `update_available=true|false` to `$GITHUB_OUTPUT`.
- `apply.sh`: appends one `KEY=VALUE` line to `$PIN_UPDATES` per changed pin, and never edits `pins.env` itself. If it fails, nothing is written.

Update only your image's pins; `BASE_APP_IMAGE` is bumped repo-wide by `.github/scripts/propagate-base-digest.sh`.

Update scripts handle upstream data and their results auto-merge, so `update.yml` writes the reported values literally, only to keys that already exist, and `.github/scripts/validate-pin-changes.sh` then rejects anything other than changed values of `*_VERSION`/`*_TAG`, `*_SHA256`, `*_DIGEST`, and `*_URL` keys. A URL must keep its host, and on github.com its owner/repo. Adding keys, changing a source repo, or moving a download elsewhere is a reviewed change. The PR body is built from the validated changes, not from script output.

Try them locally with `GITHUB_OUTPUT=/dev/null bash images/<name>/update/check.sh`; `apply.sh` prints its updates when `PIN_UPDATES` is unset.

## Before opening a PR

`./tests/policy-check.sh` and the image's `tests/run-smoke.sh` both pass.
