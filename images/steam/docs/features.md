# Features

## Core Stack

| Feature          | Description                                                                    |
| ---------------- | ------------------------------------------------------------------------------ |
| **Gamescope**    | Valve's gaming compositor for frame pacing, scaling, and reduced input latency |
| **MangoHud**     | Real-time performance overlay (FPS, GPU/CPU temps, frame times)                |
| **GameMode**     | Automatic CPU governor switching and I/O priority tuning                       |
| **UMU-Launcher** | Unified Proton launcher for Windows games with better compatibility            |
| **Decky Loader** | SteamOS plugin framework for UI customizations                                 |

## Steam Modes

The image supports two Steam modes controlled by `GAMESCOPE_STEAM_MODE`:

### `off` (default) — Standard Big Picture

Steam runs in traditional Big Picture mode. You can exit Big Picture to access desktop mode for library management.

**Best for:** Managing your library, adding external games, changing settings that aren't accessible in Big Picture.

### `on` — SteamOS GamepadUI

Enables gamescope's Steam integration (`-e` flag). Steam enters the SteamOS/Deck-style interface.

**Best for:** Controller-only couch gaming, Steam Deck-like experience.

### Mode Comparison

| Feature               | `off` (default)      | `on`                                |
| --------------------- | -------------------- | ----------------------------------- |
| Steam UI              | Standard Big Picture | SteamOS GamepadUI                   |
| Exit button           | "Exit Big Picture"   | "Switch to desktop"                 |
| Power menu            | Hidden               | Shutdown / Restart / Suspend        |
| MangoHud overlay      | Visible by default   | Hidden initially (Steam-controlled) |
| MangoApp integration  | No                   | Yes (horizontal bar)                |
| Variable Rate Shading | Not available        | Enabled                             |
| Gamescope scaling     | Not available        | Enabled                             |
| Desktop mode switch   | Available            | Broken¹                             |

¹ "Switch to desktop" doesn't work in containers—there's no underlying desktop session.

## MangoHud Keyboard Shortcuts

The overlay is visible by default in standard mode. Use these shortcuts:

| Shortcut            | Function                         |
| ------------------- | -------------------------------- |
| `Right Shift + F12` | Toggle overlay on/off            |
| `Right Shift + F11` | Change position (corners/center) |
| `Right Shift + F10` | Toggle preset verbosity          |

In `GAMESCOPE_STEAM_MODE=on`, the overlay starts hidden and Steam controls visibility.

## Performance Optimizations

| Optimization              | How it works                                                                      |
| ------------------------- | --------------------------------------------------------------------------------- |
| **GameMode**              | Switches CPU to performance governor, boosts I/O priority when games run          |
| **VRS (Steam mode only)** | AMD RDNA2/3 GPUs use Variable Rate Shading for up to 20% FPS gains                |
| **vm.max_map_count**      | Prevents crashes in memory-intensive games (The Finals, Hogwarts Legacy, CS2)     |
| **Newer Mesa/drivers**    | Fedora 43 ships newer Mesa than Ubuntu LTS—better Vulkan performance on AMD/Intel |

## Container Lifecycle

The container runs while Steam runs. When Steam exits, the session ends.

**Standard mode:**

- Exit Big Picture → Desktop mode (keep managing library)
- Exit Steam → Session ends

**SteamOS mode:**

- Power Off/Restart/Suspend buttons → Session ends (intercepted, won't shut down host)
- "Switch to desktop" → Doesn't work (no desktop session)
