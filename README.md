# GoW Collection

Custom Docker images for [Games on Whales](https://github.com/games-on-whales/gow) / [Wolf](https://github.com/games-on-whales/wolf).

The images are meant to be used as Wolf Docker apps.

## Images

| Image                                           | What it is                                                         | Pull                                                           |
| ----------------------------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------- |
| [drop-app](images/drop-app/README.md)           | [Drop](https://github.com/Drop-OSS/drop-app) desktop client        | `docker pull ghcr.io/Baz00k/gow-collection/drop-app:edge`      |
| [prism-offline](images/prism-offline/README.md) | Offline-capable [Prism Launcher](https://prismlauncher.org/) image | `docker pull ghcr.io/Baz00k/gow-collection/prism-offline:edge` |
| [steam](images/steam/README.md)                 | Steam with gamescope, MangoHud, GameMode, and Decky Loader         | `docker pull ghcr.io/Baz00k/gow-collection/steam:edge`         |

## Start Here

- [Common runtime](docs/common-runtime.md): shared user, debug, host tuning, and tag behavior.
- [Troubleshooting](docs/troubleshooting.md): common permission, GPU, startup, and game-crash issues.

Each image README includes its Wolf app example and image-specific settings.

## Updates And Safety

Dependency updates are automated with pull requests. Automated PRs are only merged after policy checks and image build/smoke tests pass.

## Repository Layout

```text
gow-collection/
├── docs/                    # Shared user docs
├── images/
│   └── <name>/
│       ├── build/           # Dockerfile, pins.env, startup script, overlay
│       ├── tests/           # Smoke tests
│       ├── update/          # Optional dependency update scripts
│       └── README.md        # Image-specific notes
├── tests/                   # Repository policy checks
└── .github/workflows/       # Build, publish, update, and auto-merge workflows
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add or update images.

## License

GPL-3.0-only
