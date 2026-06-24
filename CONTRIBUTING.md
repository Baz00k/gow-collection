# Contributing

All image-specific logic lives under `images/<name>/`. Adding an image never requires touching workflow files — CI auto-discovers images via `images/*/build/pins.env`.

## Adding an image

```
images/<name>/
├── build/
│   ├── Dockerfile
│   ├── pins.env
│   ├── overlay/          # copied to / in the image (e.g. opt/gow/startup.sh)
│   └── .dockerignore
├── tests/
│   ├── run-smoke.sh
│   └── smoke-*.sh
├── update/               # optional: check.sh + apply.sh
└── README.md
```

App Dockerfiles declare `ARG BASE_APP_IMAGE` and use a single `FROM ${BASE_APP_IMAGE}`. Shared runtime behavior comes from the base image — keep image READMEs to what's specific to that image plus a Wolf app example. Common runtime and troubleshooting live in `docs/`.

## pins.env

```bash
# Must pin the base by sha256 digest — floating tags break reproducibility.
BASE_APP_IMAGE=ghcr.io/<owner>/gow-collection/base:edge@sha256:<digest>

APP_VERSION=1.2.3
APP_SHA256=<sha256-of-artifact>
```

App update scripts must not modify `BASE_APP_IMAGE`; base-digest propagation is owned by `.github/scripts/propagate-base-digest.sh`.

## Update scripts

Optional `update/check.sh` and `update/apply.sh` (both executable) communicate with CI via `$GITHUB_OUTPUT` and receive `PINS_FILE` and `IMAGE_DIR`:

- `check.sh` → `update_available=true|false` (+ optional `summary_md` heredoc)
- `apply.sh` → `applied=true|false` (+ optional `summary_md` heredoc)

## Before opening a PR

Run `./tests/policy-check.sh` and the image's `tests/run-smoke.sh`.
