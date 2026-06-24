# Contributing

## Adding a New Image

All image-specific logic lives under `images/<name>/`. Adding an image never requires creating or modifying workflow files.

### Directory Structure

```
images/{name}/
├── build/
│   ├── Dockerfile
│   ├── pins.env
│   ├── scripts/
│   │   └── startup.sh
│   └── .dockerignore
├── tests/
│   ├── run-smoke.sh
│   └── smoke-*.sh
├── update/                  # Optional: automated dependency updates
│   ├── check.sh
│   └── apply.sh
└── README.md
```

### Required Files

- `build/Dockerfile`: Container definition
- `build/pins.env`: Dependency versions with digest pinning
- `build/scripts/startup.sh`: Container startup script
- `build/.dockerignore`: Build context filter
- `tests/run-smoke.sh`: Smoke test orchestrator
- `README.md`: Image documentation

Image READMEs should describe only what is specific to that image and include a Wolf app example. Shared runtime behavior belongs in `docs/common-runtime.md`, and common troubleshooting belongs in `docs/troubleshooting.md`.

### Optional: Dependency Updates

Add `update/check.sh` and `update/apply.sh` for automated version updates. Both scripts must be executable.

## pins.env Format

```bash
# Base image MUST include sha256 digest
BASE_APP_IMAGE=ghcr.io/<owner>/gow-collection/base:edge@sha256:<digest>

# App-specific versions
APP_VERSION=1.2.3
APP_SHA256=def456...
```

Always pin base images to a digest. Floating tags break reproducibility. App update scripts must not modify `BASE_APP_IMAGE`; base digest propagation is owned solely by `.github/scripts/propagate-base-digest.sh`.

## Smoke Tests

Create `tests/run-smoke.sh` that orchestrates individual tests:

```bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-ghcr.io/Baz00k/gow-collection/{name}:test}"
EVIDENCE_DIR="test-results/{name}"

./tests/smoke-startup.sh
./tests/smoke-deps.sh
```

Individual test scripts (`smoke-*.sh`) verify specific functionality and write evidence to `$EVIDENCE_DIR/`.

## Update Script Contract

Scripts communicate with CI via `GITHUB_OUTPUT`. Output these keys:

### check.sh

```bash
# Required
echo "update_available=true" >> "$GITHUB_OUTPUT"

# Optional: summary for PR body (markdown)
echo "summary_md<<EOF" >> "$GITHUB_OUTPUT"
echo "- Updated APP_VERSION from 1.2.3 to 1.2.4" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"
```

Set `update_available=false` if no updates found.

### apply.sh

```bash
# Required
echo "applied=true" >> "$GITHUB_OUTPUT"

# Optional: summary for PR body (markdown)
echo "summary_md<<EOF" >> "$GITHUB_OUTPUT"
echo "Updated pins.env with new versions" >> "$GITHUB_OUTPUT"
echo "EOF" >> "$GITHUB_OUTPUT"
```

Both scripts receive these environment variables:

- `PINS_FILE`: Path to `images/{name}/build/pins.env`
- `IMAGE_DIR`: Path to `images/{name}/`

## CI Workflows

Global workflows are generic and auto-discover images. No per-image workflow files needed.
