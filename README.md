# GoW Collection

My collection of Docker images for [Games on Whales](https://github.com/games-on-whales/gow) / [Wolf](https://github.com/games-on-whales/wolf).

## Images

| Image                                           | Description                                                       | Pull                                                           |
| ----------------------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------- |
| [drop-app](images/drop-app/README.md)           | [Drop](https://github.com/Drop-OSS/drop-app) game launcher        | `docker pull ghcr.io/Baz00k/gow-collection/drop-app:edge`      |
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

## Automation

All builds and updates are automated and the images should be kept up to date.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add new images.

## License

GPL-3.0-only
