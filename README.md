# GoW Collection

Self-contained Docker image monorepo for [Games on Whales](https://github.com/games-on-whales/gow) / [Wolf](https://github.com/games-on-whales/wolf) streaming platform. Adding a new image requires no workflow file changes, just create the image directory.

## Images

| Image | Description | Pull |
|-------|-------------|------|
| [drop-app](images/drop-app/README.md) | [Drop](https://github.com/Drop-OSS/drop-app) game launcher | `docker pull ghcr.io/Baz00k/gow-collection/drop-app:edge` |
| [prism-offline](images/prism-offline/README.md) | [Prism Launcher](https://prismlauncher.org/) with offline support | `docker pull ghcr.io/Baz00k/gow-collection/prism-offline:edge` |

## Repository Structure

```
gow-collection/
├── images/
│   └── <name>/
│       ├── build/           # Dockerfile, pins.env, scripts
│       ├── tests/           # Smoke tests
│       ├── update/          # Dependency update scripts (optional)
│       │   ├── check.sh     # Check for available updates
│       │   └── apply.sh     # Apply updates to pins.env
│       └── README.md
├── .github/workflows/
│   ├── images.yml                    # Orchestrator: discovers changed images
│   ├── docker-build-and-publish.yml  # Reusable build workflow
│   ├── update-deps.yml               # Discovers image-local update scripts
│   └── policy.yml                    # Policy checks
└── tests/                            # Global policy checks
```

## CI/CD

Builds are handled by generic workflows that discover images automatically:

- **`images.yml`** - Orchestrator that detects which images changed (via git diff) and builds only those. Uses matrix strategy to parallelize builds.
- **`docker-build-and-publish.yml`** - Reusable workflow called by `images.yml` for each image. Handles Docker build, tagging, and publishing to GHCR.

No per-image workflow files are needed. Adding a new image under `images/` with a `build/pins.env` is all that's required.

## Dependency Updates

Automated dependency updates via **`update-deps.yml`**:

1. Discovers all executable `images/*/update/check.sh` scripts
2. Runs each `check.sh` to detect available updates
3. If updates found, runs the corresponding `apply.sh` to update `pins.env`
4. Creates a single PR with all updates

To opt in, add executable `check.sh` and `apply.sh` scripts to your image's `update/` directory.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add new images.

## License

GPL-3.0-only
