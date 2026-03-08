# AGENTS.md

## Project Overview

Docker image collection for [Games on Whales](https://github.com/games-on-whales/gow) / [Wolf](https://github.com/games-on-whales/wolf). Each image lives under `images/<name>/` with a standardized directory structure. There is no application source code — only Dockerfiles, bash scripts, and GitHub Actions workflows.

## Repository Structure

```
images/<name>/
├── build/
│   ├── Dockerfile          # Container definition
│   ├── pins.env            # Pinned dependency versions (tracked by git)
│   ├── scripts/startup.sh  # Container startup script
│   └── .dockerignore
├── tests/
│   ├── run-smoke.sh        # Test orchestrator — runs all smoke-*.sh
│   └── smoke-*.sh          # Individual smoke test scripts
├── update/                 # Optional: automated dependency updates
│   ├── check.sh            # Detects available updates
│   └── apply.sh            # Applies updates to pins.env
└── README.md

tests/                      # Global policy checks
.github/workflows/          # CI — never needs per-image modifications
```

## Build & Test Commands

### Policy Check (no Docker required)

```bash
# Run all policy checks (floating refs, unverified downloads, secrets)
./tests/policy-check.sh

# Strict mode — warnings also fail
./tests/policy-check.sh --strict

# Single image only
./tests/policy-check.sh images/drop-app
```

### Docker Build (single image)

```bash
# Build from pins.env build-args
docker build \
  --build-arg BASE_APP_IMAGE="$(grep BASE_APP_IMAGE images/<name>/build/pins.env | cut -d= -f2)" \
  -t gow-collection/<name>:test \
  images/<name>/build/
```

### Smoke Tests (require Docker + built image)

```bash
# Run full smoke suite for an image
IMAGE_NAME="gow-collection/<name>:test" images/<name>/tests/run-smoke.sh

# Run a single smoke test
IMAGE_NAME="gow-collection/<name>:test" images/<name>/tests/smoke-startup.sh

# Skip build step (image already loaded)
SKIP_BUILD=true IMAGE_NAME="..." images/<name>/tests/run-smoke.sh
```

Test evidence is written to `test-results/<name>/` (gitignored).

### Update Scripts (check for upstream changes)

```bash
# Check if updates are available
GITHUB_OUTPUT=/dev/null bash images/<name>/update/check.sh

# Apply updates to pins.env
GITHUB_OUTPUT=/dev/null bash images/<name>/update/apply.sh
```

## CI Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `images.yml` | Push/PR changing `images/**` | Discovers changed images, triggers builds |
| `docker-build-and-publish.yml` | Called by images.yml | Build → smoke test → publish (reusable) |
| `policy.yml` | Push/PR to main | Runs `./tests/policy-check.sh --strict` |
| `update-deps.yml` | Weekly (Mon 06:00 UTC) | Auto-discovers `update/check.sh`, creates PRs |

Adding an image under `images/` with `build/pins.env` is all that's needed for CI integration. No workflow files need modification.

## Code Style & Conventions

### Shell Scripts (Bash)

**Shebang**: Use `#!/bin/bash` for scripts, `#!/usr/bin/env bash` for update scripts.

**Error handling**: Always `set -euo pipefail` at the top of every script.

**Variable quoting**: Always double-quote variables — `"${VAR}"` not `$VAR`. Use `${VAR:-default}` for optional env vars with defaults.

**Naming conventions**:
- Variables: `UPPER_SNAKE_CASE` for environment variables and script-level vars
- Functions: `lower_snake_case` (e.g., `log_info`, `fetch_latest_base_digest`)
- File names: `kebab-case` (e.g., `run-smoke.sh`, `smoke-startup.sh`, `policy-check.sh`)
- Test scripts: Prefix with `smoke-` (e.g., `smoke-startup.sh`, `smoke-deps.sh`)

**Logging**: Use colored log functions. Standard pattern:

```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
```

**Cleanup**: Use `trap cleanup EXIT` for container/temp file cleanup.

**Portable sed**: Use the `inplace()` wrapper for in-place sed (no `-i` flag):

```bash
inplace() { sed "$1" "$2" > "${2}.tmp" && mv "${2}.tmp" "$2"; }
```

**Error exit**: Use `abort() { echo "ERROR: $1" >&2; exit 1; }` for fatal errors.

### Dockerfiles

- Start with `# syntax=docker/dockerfile:1.4`
- Use `ARG BASE_APP_IMAGE` and `FROM ${BASE_APP_IMAGE}` (base image comes from pins.env)
- Use hadolint ignore comments where needed: `# hadolint ignore=DL3006,DL3008`
- Always verify downloads with `sha256sum -c -`
- Clean apt caches: `apt-get clean && rm -rf /var/lib/apt/lists/*`
- Copy startup script to `/opt/gow/startup-app.sh` with `--chmod=755` (or `--chmod=777`)
- Set `ENV XDG_RUNTIME_DIR=/tmp/.X11-unix`
- Add OCI labels at the end: `org.opencontainers.image.{title,description,authors,source,licenses}`

### pins.env Format

```bash
# Base image MUST include sha256 digest — floating tags break reproducibility
BASE_APP_IMAGE=ghcr.io/games-on-whales/base-app:edge@sha256:<digest>

# App-specific pinned versions
APP_VERSION=1.2.3
APP_SHA256=<sha256-of-downloaded-artifact>
```

### Smoke Tests

Each test script follows this structure:
1. Parse env vars (`IMAGE_NAME`, `CONTAINER_NAME`, `EVIDENCE_DIR`)
2. Write evidence header to `EVIDENCE_FILE`
3. Set `trap cleanup EXIT` to remove containers
4. Verify image exists with `docker image inspect`
5. Run container with `docker run -d --entrypoint "" ... sleep infinity`
6. Execute checks via `docker exec`
7. Write results to evidence file
8. Exit 0 on pass, exit 1 on failure

### Update Scripts Contract

Scripts communicate with CI via `GITHUB_OUTPUT`:
- `check.sh` outputs: `update_available=true|false`, optional `summary_md`
- `apply.sh` outputs: `applied=true|false`, optional `summary_md`
- Both receive: `PINS_FILE` and `IMAGE_DIR` env vars from CI
- Both must be executable (`chmod +x`)

## Security Rules

- **Always pin base images to sha256 digest** — never use floating tags alone
- **Always verify downloaded artifacts** with sha256 checksums
- **Never commit secrets** — `.env` files are gitignored (except `pins.env`)
- Policy check enforces: no floating refs, no unverified downloads, no secrets in tracked files

## Adding a New Image

1. Create `images/<name>/build/Dockerfile`, `build/pins.env`, `build/scripts/startup.sh`, `build/.dockerignore`
2. Create `images/<name>/tests/run-smoke.sh` and individual `smoke-*.sh` tests
3. Create `images/<name>/README.md`
4. Optionally add `images/<name>/update/check.sh` and `update/apply.sh`
5. No workflow changes needed — CI auto-discovers via `images/*/build/pins.env`

See [CONTRIBUTING.md](CONTRIBUTING.md) for full details.
