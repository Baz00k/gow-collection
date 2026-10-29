# AGENTS.md

Docker images for [Games on Whales](https://github.com/games-on-whales/gow) / [Wolf](https://github.com/games-on-whales/wolf): Dockerfiles, bash, and GitHub Actions, one directory per image under `images/`. Before adding an image or writing update scripts, read [CONTRIBUTING.md](CONTRIBUTING.md).

## Base image and pinning

`images/base/` owns the shared runtime (entrypoint, runtime user, cont-init, GPU/device setup, Flatpak sandboxing). App images build `FROM ${BASE_APP_IMAGE}` and add only packages plus an overlay `startup.sh`; reach for the base before duplicating runtime logic in an app.

- The base pins Fedora by tag **and** digest, because the Fedora registry garbage-collects old digests. Apps pin the base by digest on our GHCR, which keeps them.
- Each `update/` script owns only its own image's dependencies. `BASE_APP_IMAGE` belongs to `.github/scripts/propagate-base-digest.sh`, run from `update.yml`.
- App images inherit the base's `XDG_RUNTIME_DIR`; override it only with a concrete reason.

## Commands

```bash
./tests/policy-check.sh [images/<name>]   # run after every change

# Build with every pin as a build-arg, as CI does
mapfile -t ARGS < <(.github/scripts/pins-to-build-args.sh images/<name>)
docker build "${ARGS[@]/#/--build-arg=}" -t gow-collection/<name>:test images/<name>/build/

IMAGE_NAME=gow-collection/<name>:test images/<name>/tests/run-smoke.sh   # evidence in test-results/<name>/
```
