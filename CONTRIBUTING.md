# Contributing

## Adding a New Image

### 1. Create Directory Structure

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
└── README.md
```

### 2. Required Files Checklist

- [ ] `build/Dockerfile`: Container definition
- [ ] `build/pins.env`: Dependency versions with digest pinning
- [ ] `build/scripts/startup.sh`: Container startup script
- [ ] `build/.dockerignore`: Build context filter
- [ ] `tests/run-smoke.sh`: Smoke test orchestrator
- [ ] `README.md`: Image documentation

### 3. pins.env Format

Dependency versions and digests go in `build/pins.env`:

```bash
# Base image MUST include sha256 digest
BASE_APP_IMAGE=ghcr.io/games-on-whales/base-app:edge@sha256:abc123...

# App-specific versions
APP_VERSION=1.2.3
APP_SHA256=def456...
```

**Critical**: Always pin base images to a digest. Floating tags break reproducibility.

### 4. Smoke Tests

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

### 5. CI Integration

Create `.github/workflows/{name}.yml`:

```yaml
name: {name}

on:
  push:
    branches: [main]
    paths: ['images/{name}/**']
  pull_request:
    paths: ['images/{name}/**']
  workflow_dispatch:

jobs:
  ci:
    uses: ./.github/workflows/docker-build-and-publish.yml
    with:
      image-dir: images/{name}
      image-name: {name}
```

### 6. Dependency Updates

Add update scripts in `.github/scripts/`:

- `check-{name}.sh`: Check for new versions
- `update-{name}.sh`: Update pins.env

Both scripts should accept `PINS_FILE` env var pointing to the pins.env path.

Update `.github/workflows/update-deps.yml` to call your check script for the new image.
