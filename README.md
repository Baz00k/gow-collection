# GoW Collection

Ready-to-use Docker images for [Games on Whales](https://github.com/games-on-whales/gow) / [Wolf](https://github.com/games-on-whales/wolf). Each image is a self-contained app you can stream through Wolf — no building required.

## Available Images

| Image                                           | What it is                                                   | Image reference                                    |
| ----------------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------- |
| [drop-app](images/drop-app/README.md)           | [Drop](https://github.com/Drop-OSS/drop-app) desktop client  | `ghcr.io/Baz00k/gow-collection/drop-app:edge`      |
| [prism-offline](images/prism-offline/README.md) | Offline-capable [Prism Launcher](https://prismlauncher.org/) | `ghcr.io/Baz00k/gow-collection/prism-offline:edge` |
| [steam](images/steam/README.md)                 | Steam with gamescope, MangoHud, GameMode, and Decky Loader   | `ghcr.io/Baz00k/gow-collection/steam:edge`         |

## How To Use

These images run as **Wolf Docker apps**. To add one:

1. Pick an image from the table above and open its README (linked in the first column).
2. Copy the `[[profiles.apps]]` snippet from that README into your Wolf `config.toml`.
3. Adjust any image-specific settings (e.g. server URL, env vars) as noted in the README.
4. Restart Wolf and the app appears in your client.

Wolf pulls the image automatically on first launch — you don't need to `docker pull` anything yourself.

New to Wolf? See the [Wolf documentation](https://games-on-whales.github.io/wolf/stable/) for installation and how `config.toml` works.

## Shared Documentation

- [Common runtime](docs/common-runtime.md) — shared env vars (`PUID`, `PGID`, `GOW_DEBUG`, `GAMESCOPE_*`), host tuning, and image tags.
- [Troubleshooting](docs/troubleshooting.md) — permission, GPU, startup, and game-crash issues.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add or update images.

## License

GPL-3.0-only
