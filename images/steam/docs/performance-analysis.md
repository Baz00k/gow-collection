# Steam Fedora Image — Performance Analysis

## Executive Summary

This document outlines the performance optimization strategy for the Fedora 43-based Steam image, expected performance gains compared to the Ubuntu-based GoW base-app baseline, and the methodology for measuring each optimization's impact.

The Fedora image leverages Bazzite-inspired tuning patterns while respecting container constraints. Key optimizations include GameMode for CPU prioritization, MangoHud for real-time metrics, Variable Rate Shading (VRS) for AMD GPUs, gamescope for frame pacing, and sysctl tuning where container capabilities permit.

**Key Insight**: Performance gains are workload-dependent and best measured relative to the user's existing setup. Container images cannot guarantee absolute performance improvements—only that optimizations are correctly applied and measurable.

---

## Baseline Comparison: Fedora 43 vs Ubuntu/GoW base-app

### Kernel and Driver Versions

| Component | Ubuntu/GoW base-app | Fedora 43 Image | Expected Impact |
|-----------|---------------------|-----------------|-----------------|
| Kernel | LTS kernel (older, stable) | Fedora 43 kernel (newer, ~6.x) | Newer kernels include gaming-specific fixes, improved scheduler, better AMD support |
| Mesa | Ubuntu LTS version (older) | Fedora 43 Mesa (newer) | Better Vulkan conformance, improved RADV performance, newer OpenGL features |
| Steam | apt package | RPM Fusion package | Same binary, different packaging; no performance difference expected |
| gamescope | apt package | Fedora package | Same upstream; version may differ slightly |

### Package Freshness

Fedora 43's rolling-release model provides more recent versions of:
- **Mesa drivers**: Access to latest RADV/Intel Vulkan improvements, ray tracing optimizations
- **Vulkan loader**: Newer API support, bug fixes
- **gamescope**: Latest compositor features, HDR improvements
- **gamemode**: Current Feral Interactive releases

**Quantifiable Signal**: Mesa version numbers reported by `vulkaninfo --summary` or `glxinfo | grep "OpenGL version"`.

---

## Performance Optimizations Implemented

### Optimization Summary Table

| Feature | Expected Impact | Measurement Method | Evidence Source |
|---------|-----------------|-------------------|-----------------|
| **GameMode** | 5-15% FPS improvement in CPU-bound scenarios | `gamemoded -s` status check; FPS comparison via MangoHud | [Feral Interactive](https://github.com/FeralInteractive/gamemode) — developer benchmarks show CPU governor + I/O priority tuning improves frame rates in CPU-limited games |
| **MangoHud/MangoApp** | <1% FPS overhead; provides real-time metrics | FPS comparison with/without MangoHud; frame timing graph | [MangoHud GitHub](https://github.com/flightlessmango/MangoHud) — lightweight Vulkan/OpenGL overlay |
| **Variable Rate Shading (VRS)** | 10-20% FPS improvement on AMD RDNA2/RDNA3 | `RADV_FORCE_VRS=2x2` env var; FPS measurement via MangoHud | [Phoronix RADV VRS Benchmarks](https://www.phoronix.com/review/radeon-radv-vrs) — 2x2 VRS mode tested on RX 6000 series |
| **Gamescope compositor** | Improved frame pacing; reduced input latency | Frame time graph consistency via MangoHud; input latency measurement | [Steam Deck / Gamescope](https://github.com/ValveSoftware/gamescope) — Valve's compositor for SteamOS |
| **vm.max_map_count tuning** | Prevents crashes in memory-intensive games; reduces stuttering | `sysctl vm.max_map_count` value check; game stability | [Arch Linux Gaming](https://gamingonlinux.com/2024/04/arch-linux-changes-vmmax_map_count-to-match-fedora-ubuntu-for-better-gaming) — 1048576 prevents crashes in The Finals, Hogwarts Legacy, DayZ, CS2 |
| **kernel.sched_* tuning** | Potentially reduced CPU scheduling latency | `sysctl` value checks; micro-benchmark results | Container-dependent; may not apply without elevated capabilities |
| **Newer Mesa/kernel** | GPU driver improvements; new Vulkan features | `vulkaninfo --summary` for version; game-specific benchmarks | Mesa release notes document per-version improvements |

### Detailed Feature Analysis

#### 1. GameMode

**What it does**: GameMode is a daemon/library combo from Feral Interactive that optimizes system parameters when games are running:
- Switches CPU governor to `performance` mode
- Sets I/O priority to real-time for game process
- Adjusts process niceness
- Disables screensaver during gameplay
- Inhibits desktop compositor effects (where applicable)

**Expected Impact**: 5-15% FPS improvement in CPU-bound scenarios. Less impact on GPU-bound games.

**Measurement Method**:
```bash
# Check GameMode status
gamemoded -s

# Expected output when active: "gamemode is active and running"

# FPS comparison (run game twice, with and without gamemoderun)
gamemoderun %command%  # Steam launch option
```

**Evidence Source**: Feral Interactive's [GameMode repository](https://github.com/FeralInteractive/gamemode) documents the optimization approach and provides benchmark methodology.

#### 2. MangoHud / MangoApp

**What it does**: Lightweight Vulkan/OpenGL overlay providing real-time performance metrics:
- FPS counter with frame timing graph
- CPU/GPU utilization percentages
- Memory usage (RAM/VRAM)
- Temperature monitoring
- Configurable display options

**Expected Impact**: <1% FPS overhead when enabled. The performance cost is negligible; primary value is measurement capability.

**Measurement Method**:
```bash
# Enable MangoHud
MANGOHUD=1 %command%  # Steam launch option

# Check MangoHud is running
pgrep -f mangohud

# Verify FPS impact (compare with MANGOHUD=0)
```

**Evidence Source**: [MangoHud GitHub](https://github.com/flightlessmango/MangoHud) — designed for minimal overhead monitoring.

#### 3. Variable Rate Shading (VRS)

**What it does**: VRS allows the GPU to reduce shading rate in less visually important areas, trading visual quality for performance. The RADV driver supports forcing VRS via environment variable.

**Expected Impact**: 10-20% FPS improvement on AMD RDNA2 (RX 6000 series) and RDNA3 (RX 7000 series) GPUs with minimal visible quality loss at 2x2 mode.

**Measurement Method**:
```bash
# Enable VRS 2x2 mode
RADV_FORCE_VRS=2x2 %command%  # Steam launch option

# Verify VRS is active (Mesa debug output)
RADV_DEBUG=vrs %command%

# FPS comparison with RADV_FORCE_VRS unset
```

**Evidence Source**: [Phoronix RADV VRS Benchmarks](https://www.phoronix.com/review/radeon-radv-vrs) — Michael Larabel tested 2x2 VRS override on RDNA2 hardware showing significant FPS gains with acceptable quality trade-off.

**Limitation**: VRS only works on AMD RDNA2/RDNA3 GPUs with Mesa RADV driver. Intel/NVIDIA require different approaches.

#### 4. Gamescope Compositor

**What it does**: Valve's gamescope is a Wayland compositor designed for gaming:
- Frame pacing and vsync control
- Integer scaling support
- HDR support (where available)
- Nested mode for running games in a window
- FPS limiting with better frame pacing than Steam's built-in limiter

**Expected Impact**: 
- Improved frame pacing (more consistent frame times)
- Reduced input latency vs. desktop compositors
- Better performance at non-native resolutions via scaling

**Measurement Method**:
```bash
# Verify gamescope is running
pgrep -f gamescope

# Check gamescope stats socket (if configured)
ls -la /tmp/gamescope-stats.txt

# Frame time graph in MangoHud shows consistency
```

**Evidence Source**: [Gamescope GitHub](https://github.com/ValveSoftware/gamescope) — Valve's compositor powering Steam Deck gaming mode.

**Caveat**: Gamescope's built-in FPS limiter can add input latency (~1-2 frames). For competitive gaming, prefer `MANGOHUD_CONFIG=fps_limit=X` over gamescope's limiter.

#### 5. sysctl Performance Tuning

**What it does**: Kernel parameter tuning for gaming workloads:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `vm.max_map_count` | 1048576 | Prevents memory mapping failures in large games (The Finals, DayZ, CS2) |
| `kernel.sched_autogroup_enabled` | 0 | Disables autogroup for potentially lower latency |
| `net.core.rmem_max` | 2097152 | Increased network buffer for online gaming |
| `net.core.wmem_max` | 2097152 | Increased network buffer for online gaming |

**Expected Impact**: 
- `vm.max_map_count`: Prevents crashes/stutters in memory-intensive games
- Scheduler tuning: Marginal improvement, workload-dependent
- Network tuning: Potentially reduced network latency in online games

**Measurement Method**:
```bash
# Check current values
sysctl vm.max_map_count
sysctl kernel.sched_autogroup_enabled

# Expected output
vm.max_map_count = 1048576
```

**Evidence Source**: [GamingOnLinux](https://gamingonlinux.com/2024/04/arch-linux-changes-vmmax_map_count-to-match-fedora-ubuntu-for-better-gaming) — Arch, Fedora, and Ubuntu all ship higher `vm.max_map_count` defaults for gaming compatibility.

**Container Limitation**: sysctl changes require elevated capabilities. Container may not be able to set these values; tuning script logs skipped settings with warnings.

---

## Container-Specific Considerations

### What Works in Containers

| Optimization | Container-Feasible | Notes |
|--------------|-------------------|-------|
| GameMode | Yes | Daemon runs in container; affects container processes |
| MangoHud | Yes | Overlay injects into game process |
| VRS | Yes | Environment variable; no kernel access needed |
| gamescope | Yes | Compositor runs in container |
| vm.max_map_count | Limited | Requires `--sysctl` at container start or privileged mode |
| kernel.sched_* | Limited | Same as above |

### GPU Driver Model

This image follows the **Wolf runtime model**:
- Container does NOT bundle GPU drivers
- Host GPU drivers are passed through via volume mounts
- Container provides userspace libraries (Mesa, Vulkan loader) compatible with host driver
- NVIDIA support requires host-installed driver + nvidia-container-toolkit

**Implication**: GPU performance depends entirely on host driver version, not container contents. Fedora 43's newer Mesa benefits AMD/Intel users; NVIDIA users get host driver performance.

### No Kernel Control

Container images cannot:
- Change kernel scheduler parameters at runtime (without `--privileged`)
- Install kernel modules
- Modify host kernel boot parameters

Workaround: Document required host-side settings for users who want maximum performance.

---

## Measurement Methodology

### How to Verify Optimizations Are Active

Each optimization can be verified programmatically:

```bash
# GameMode
gamemoded -s  # Returns "gamemode is active and running"

# MangoHud
pgrep -f mangohud && echo "MangoHud running"

# VRS (check environment in game process)
cat /proc/$(pgrep -f steam)/environ | tr '\0' '\n' | grep RADV_FORCE_VRS

# gamescope
pgrep -f gamescope && echo "gamescope running"

# sysctl values
sysctl vm.max_map_count  # Should show 1048576
```

### Metrics to Collect

| Metric | Tool | Purpose |
|--------|------|---------|
| Average FPS | MangoHud, Steam FPS counter | Primary performance indicator |
| 1% Low FPS | MangoHud frame timing | Worst-case performance |
| Frame time variance | MangoHud graph | Frame pacing quality |
| CPU utilization | MangoHud, `htop` | CPU-bound vs GPU-bound analysis |
| GPU utilization | MangoHud, `radeontop` | GPU saturation level |
| Memory usage | MangoHud | VRAM/system RAM consumption |

### Benchmark Protocol

For reproducible measurements:

1. **Establish baseline**: Run game without optimizations, record FPS via MangoHud
2. **Enable single optimization**: Add one optimization at a time
3. **Record delta**: Note FPS change, 1% low, frame time variance
4. **Test multiple scenarios**: CPU-bound (low settings), GPU-bound (high settings), memory-intensive (large maps)
5. **Document hardware**: GPU model, driver version, Mesa version affect results

---

## Limitations and Caveats

### Performance Claims Are Estimates

All percentage improvements in this document are:
- Based on published benchmarks from external sources
- Workload-dependent (different games show different gains)
- Hardware-dependent (GPU model, CPU, RAM affect results)
- NOT guaranteed for any specific user configuration

**Correct framing**: "Up to 15% improvement in CPU-bound scenarios" not "15% FPS boost".

### Container Overhead

Running in a container adds minimal but measurable overhead:
- Additional process isolation layers
- Filesystem overlay (if not using volume mounts)
- Network namespace (unless `--net=host`)

In practice, this overhead is typically <1-2% FPS and is outweighed by optimization benefits.

### GPU Driver Version Dependency

For AMD/Intel users:
- Container's Mesa version determines Vulkan/OpenGL feature support
- Fedora 43's Mesa is typically newer than Ubuntu LTS

For NVIDIA users:
- Performance depends entirely on host driver version
- Container cannot improve NVIDIA performance beyond host driver capabilities

### VRS Limitations

Variable Rate Shading:
- Only works on AMD RDNA2/RDNA3 GPUs
- Requires Mesa RADV driver (not AMDGPU-PRO)
- May cause visual artifacts in some games
- Quality loss is trade-off for performance gain

### gamescope FPS Limiter Latency

The gamescope built-in FPS limiter (`-r` flag) can add significant input latency at low framerates:
- 30 FPS limit: ~50-100ms additional latency reported
- Alternative: Use MangoHud's FPS limiter (`MANGOHUD_CONFIG=fps_limit=30`)

---

## Conclusion

The Fedora 43 Steam image implements a set of well-documented, measurable performance optimizations. While absolute performance gains depend on hardware and workload, each optimization is:

1. **Verifiable**: Commands exist to confirm optimization is active
2. **Measurable**: FPS/frame time metrics quantify impact
3. **Reversible**: Optimizations can be disabled for comparison
4. **Documented**: External benchmarks support expected impact ranges

Users should benchmark their own setups to determine actual gains. The value of this image is in providing a curated, tested set of optimizations rather than guaranteed performance numbers.

---

*Document finalized 2026-03-09. All optimizations implemented and documented.*
