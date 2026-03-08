# GoW Prism Launcher (Offline-Enabled)

A Games on Whales (Wolf) custom Docker image for Prism Launcher with offline account support.

## Overview

This project provides a containerized Prism Launcher image designed for use with [Wolf](https://github.com/games-on-whales/wolf), the Games on Whales streaming platform. The image supports offline/local profiles for LAN play and servers configured with `online-mode=false`.

> **Note:** This is a launcher container only. No Minecraft game assets are bundled.

## Features

- Prism Launcher in a Wolf-compatible container
- Offline/local profile support for LAN and offline-server play
- GPU acceleration (NVIDIA and AMD)
- Published to GitHub Container Registry (GHCR)

## Usage

```bash
docker pull ghcr.io/Baz00k/gow-collection/prism-offline:edge
```

## Legal & Usage

**IMPORTANT:** Read [LEGAL.md](./LEGAL.md) before using this image.

- Users must own a legitimate Minecraft license for gameplay
- Offline profiles are for local/LAN play or `online-mode=false` servers only
- This project does NOT bypass Mojang/Microsoft authentication
- Certain launchers are prohibited due to security concerns

## License

GPL-3.0-only — see [LICENSE](/LICENSE)
