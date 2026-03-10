# Performance Optimizations

This image includes several components that affect game performance.

## Gamescope

Gamescope is the display server — it's how Steam renders to the screen. It's included because Wolf's virtual compositor expects a Wayland or X11 session, and gamescope provides a minimal, gaming - focused compositor that integrates well with this workflow.

The container runs gamescope with these flags by default:

- `-W ${GAMESCOPE_WIDTH}` / `-H ${GAMESCOPE_HEIGHT}` — display resolution
- `-r ${GAMESCOPE_REFRESH}` — refresh rate
- `${GAMESCOPE_MODE}` — usually `-b` for borderless window
- `-e` — Steam integration (only in SteamOS mode)

Gamescope handles scaling, frame pacing, and presents a consistent display surface to Wolf. It's not a performance optimization per se — it's infrastructure. Some users may experience different frame pacing behavior compared to running Steam directly on a desktop compositor.

## GameMode

GameMode from Feral Interactive switches the CPU governor to `performance` mode and raises I/O priority when games are running. It's implemented as a daemon that listens for the `com.feralinteractive.GameMode` D-Bus interface. Steam launches games through `gamemoderun` which signals the daemon to activate. This provides automatic performance tuning without manual intervention.

The main limitation is that it only affects processes inside the container—it cannot change the host CPU governor. On systems where the host already runs in performance mode, this provides no benefit.

## MangoHud

MangoHud is a Vulkan/OpenGL overlay that displays real-time metrics (FPS, frame times, CPU/GPU utilization, temperatures). It's included primarily as a diagnostic tool, not a performance optimization. The overlay renders in the same graphics context as the game, so the overhead is minimal, but it's not free.

MangoHud is enabled by default in standard mode (`GAMESCOPE_STEAM_MODE=off`). In SteamOS mode, it starts hidden because Steam manages its own overlay through gamescope integration. Users can toggle visibility with `Right Shift + F12`.

## Variable Rate Shading (VRS)

VRS is available only in SteamOS mode (`GAMESCOPE_STEAM_MODE=on`) and only on AMD RDNA2/RDNA3 GPUs using the Mesa RADV driver. When enabled via `RADV_FORCE_VRS=2x2`, the driver reduces shading rate in less detailed areas of the screen. This trades visual quality for GPU performance.

The environment variable is automatically set when SteamOS mode is enabled. Gamescope's `-e` flag enables Steam's VRS integration. Users who prefer maximum visual quality over performance can disable this by overriding the environment variable in their Wolf config.

## vm.max_map_count

Several modern games (The Finals, Hogwarts Legacy, DayZ, CS2) allocate large numbers of memory mappings. The default Linux limit is too low for these games, causing crashes at startup or during gameplay.

The container attempts to set `vm.max_map_count=1048576` at runtime via the startup script. This only succeeds if the container has `SYS_ADMIN` capability or the setting is passed via Docker's `--sysctl` flag. Wolf users can add this to their `apps.toml`:

```toml
[apps.steam.runner]
sysctls = ["vm.max_map_count=1048576"]
```

Without this, affected games will crash. With it, they work. There's no middle ground.

## sysctl Scheduler Tuning

The image attempts to disable `kernel.sched_autogroup_enabled` and tune network buffer sizes. These are set opportunistically - if the container has privileges, they apply; if not, the script continues without them.

The practical impact is unclear. These settings are inherited from Bazzite and other gaming distributions where they reportedly help with latency-sensitive workloads. In a container, they may do nothing if the host kernel is already tuned differently.

## Mesa Versions

Fedora 43 ships a newer Mesa than Ubuntu LTS. This is relevant because Mesa provides the userspace graphics drivers (RADV for AMD, Intel Vulkan drivers). The container includes its own Mesa libraries, which are used for AMD and Intel GPUs.

For AMD/Intel users, newer Mesa means newer Vulkan extensions and driver improvements. For NVIDIA users, this is irrelevant - the container uses the host's proprietary driver, not Mesa.

## Container Constraints

Not everything that could be tuned is tuned. The image cannot:

- Install kernel modules
- Modify host kernel boot parameters
- Change CPU governor on the host
- Access MSR registers for undervolting

These require host-level access that containers don't have. The optimizations in this image are limited to what can be done within a standard Docker container running under Wolf.
