# GoW Collection

Custom Docker images for [Games on Whales](https://github.com/games-on-whales/gow) / [Wolf](https://github.com/games-on-whales/wolf) streaming platform.

## Images

| Image | Description | Pull |
|-------|-------------|------|
| [drop-app](images/drop-app/README.md) | [Drop](https://github.com/Drop-OSS/drop-app) game launcher | `docker pull ghcr.io/Baz00k/gow-collection/drop-app:edge` |
| [prism-offline](images/prism-offline/README.md) | [Prism Launcher](https://prismlauncher.org/) with offline support | `docker pull ghcr.io/Baz00k/gow-collection/prism-offline:edge` |

## Repository Structure

```
gow-collection/
├── images/
│   ├── drop-app/
│   │   ├── build/           # Dockerfile, pins.env, scripts
│   │   ├── tests/           # Smoke tests
│   │   └── README.md
│   └── prism-offline/
│       ├── build/
│       ├── tests/
│       └── README.md
├── .github/
│   ├── workflows/           # CI/CD workflows
│   └── scripts/             # Dependency update scripts
├── tests/                   # Global policy checks
└── README.md
```

## CI Status

| Image | Build |
|-------|-------|
| drop-app | [![CI](https://github.com/Baz00k/gow-collection/actions/workflows/drop-app.yml/badge.svg)](https://github.com/Baz00k/gow-collection/actions/workflows/drop-app.yml) |
| prism-offline | [![CI](https://github.com/Baz00k/gow-collection/actions/workflows/prism-offline.yml/badge.svg)](https://github.com/Baz00k/gow-collection/actions/workflows/prism-offline.yml) |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add new images.

## License

GPL-3.0-only
