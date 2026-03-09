# Steam Fedora Image — Idea Validation

## Overview

A Fedora 43-based Docker image for running Steam via Wolf, providing a console-like gaming experience through gamescope. This image targets the Games on Whales ecosystem and prioritizes stability, minimal scope, and Wolf compatibility over broad feature support.

---

## Core Assumptions

| Assumption | Rationale | Validation Status |
|------------|-----------|-------------------|
| Fedora 43 has all required packages via official repos + RPM Fusion | Fedora's package ecosystem is mature; RPM Fusion provides Steam and multimedia codecs | ✅ **VERIFIED (T1)** |
| Gamescope-only mode is sufficient for console experience | Steam Deck uses gamescope as primary compositor; eliminates sway complexity | ✅ **PASSED (T17)** |
| Wolf runtime model handles GPU drivers (no bundled NVIDIA drivers needed) | Wolf containers share host GPU drivers via pass-through; base-app pattern proves this works | ✅ **PASSED (T2)** |
| bubblewrap capability patch from upstream GoW works on Fedora-built bwrap | GoW patches are version-agnostic; bwrap API is stable across distributions | ✅ **PASSED (T2)** |
| Steam RPM Fusion package works in containerized environment | RPM Fusion Steam is the same binary as upstream; containerization shouldn't affect runtime | ✅ **PASSED (T17)** |
| MangoApp/MangoHud available via Fedora repos | Both are in RPM Fusion nonfree; standard packages | ✅ **VERIFIED (T1)** — MangoHud in fedora repo, MangoApp bundled |

---

## Package Availability (Fedora 43)

All packages required for the Steam stack are available on Fedora 43. Below is the complete mapping of packages, their source repositories, and installation commands.

> **Note**: Fedora 43 is the current stable release.

### Repository Setup

Before installing Steam, enable RPM Fusion repositories (required for proprietary software):

```bash
# Enable RPM Fusion Free and Nonfree
dnf install \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-43.noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-43.noarch.rpm
```

These URLs are pinned in `pins.env` as `RPMFUSION_FREE_URL` and `RPMFUSION_NONFREE_URL`.

### Core Packages

| Package | Source Repo | Install Command | Notes |
|---------|-------------|-----------------|-------|
| **steam** | rpmfusion-nonfree | `dnf install steam` | Valve's Steam client. Requires RPM Fusion nonfree. |
| **gamescope** | fedora | `dnf install gamescope` | Valve's micro-compositor for gaming. Native Fedora package. |
| **bubblewrap** | fedora | `dnf install bubblewrap` | Unprivileged container runtime. Used by Steam's pressure-vessel. |

### Quality-of-Life Packages

| Package | Source Repo | Install Command | Notes |
|---------|-------------|-----------------|-------|
| **mangohud** | fedora | `dnf install mangohud` | Vulkan/OpenGL overlay for FPS, temps, CPU/GPU monitoring. |
| **mangoapp** | fedora | Included in `mangohud` | Desktop application for MangoHud. Part of mangohud package. |
| **gamemode** | fedora | `dnf install gamemode` | Daemon for on-demand game performance optimization. |

### System Services

| Package | Source Repo | Install Command | Notes |
|---------|-------------|-----------------|-------|
| **dbus-broker** | fedora | `dnf install dbus-broker` | Modern D-Bus implementation. Fedora's default since F29. |
| **dbus-daemon** | fedora | `dnf install dbus-daemon` | Legacy D-Bus. May be needed by GDM. Install alongside dbus-broker. |
| **NetworkManager** | fedora | `dnf install NetworkManager` | Network connection manager. Core Fedora package. |
| **bluez** | fedora | `dnf install bluez` | Bluetooth protocol stack. For controller support. |
| **ibus** | fedora | `dnf install ibus` | Intelligent Input Bus. Required for text input in games. |

### Utilities

| Package | Source Repo | Install Command | Notes |
|---------|-------------|-----------------|-------|
| **curl** | fedora | `dnf install curl` | HTTP client. Used for downloads. |
| **xz** | fedora | `dnf install xz` | LZMA compression. Used by Steam runtime. |
| **zenity** | fedora | `dnf install zenity` | GTK+ dialog boxes. Used by Steam helper scripts. |
| **file** | fedora | `dnf install file` | File type detection. Core utility. |
| **xdg-user-dirs** | fedora | `dnf install xdg-user-dirs` | Manages user directories (Documents, Downloads, etc.). |
| **xdg-utils** | fedora | `dnf install xdg-utils` | Desktop integration scripts (xdg-open, etc.). |
| **pciutils** | fedora | `dnf install pciutils` | PCI bus utilities (lspci). Hardware detection. |
| **mesa-demos** | fedora | `dnf install mesa-demos` | OpenGL demos and utilities (glxinfo, eglinfo). |
| **vulkan-tools** | fedora | `dnf install vulkan-tools` | Vulkan utilities (vulkaninfo). GPU diagnostics. |

### Fonts

| Package | Source Repo | Install Command | Notes |
|---------|-------------|-----------------|-------|
| **dejavu-fonts** | fedora | `dnf install dejavu-fonts` | Default Fedora fonts. Steam UI fallback. |
| **google-noto-fonts** | fedora | `dnf install google-noto-fonts` | Noto fonts for CJK and other scripts. |

### External Downloads (Pre-pinned in pins.env)

These are downloaded directly from GitHub releases, not from Fedora repos:

| Component | Source | Install Method | Notes |
|-----------|--------|----------------|-------|
| **umu-launcher** | GitHub Release | `dnf install ${UMU_LAUNCHER_URL}` | Unified Proton launcher. RPM provided by upstream. SHA256 verified. |
| **decky-loader** | GitHub Release | `curl -o /opt/decky/PluginLoader ${DECKY_LOADER_URL}` | SteamOS plugin framework. Binary download. SHA256 verified. |

### Multilib Support

Fedora handles 32-bit/multilib natively via dnf — no manual architecture enabling needed (unlike Ubuntu's `dpkg --add-architecture i386`). Steam will automatically pull in 32-bit dependencies as needed.

```bash
# Steam automatically requires 32-bit libs
dnf install steam  # Pulls in steam.i686 and 32-bit deps
```

### Install Command Summary

Single command to install all Fedora-packaged dependencies:

```bash
dnf install -y \
  steam \
  gamescope \
  bubblewrap \
  mangohud \
  gamemode \
  dbus-broker \
  dbus-daemon \
  NetworkManager \
  bluez \
  ibus \
  curl \
  xz \
  zenity \
  file \
  xdg-user-dirs \
  xdg-utils \
  pciutils \
  mesa-demos \
  vulkan-tools \
  dejavu-fonts \
  google-noto-fonts
```

### Validation Status

| Category | Status | Notes |
|----------|--------|-------|
| Core packages | ✅ Verified | All available in Fedora/RPM Fusion |
| QoL packages | ✅ Verified | MangoHud, GameMode in Fedora repos |
| System services | ✅ Verified | Standard Fedora packages |
| Utilities | ✅ Verified | All core utilities available |
| External downloads | ✅ Verified | URLs and SHA256 pinned in pins.env |
| Multilib support | ✅ Verified | Native dnf support, no manual config |

### References

- [Fedora Packages](https://packages.fedoraproject.org/) — Official package database
- [RPM Fusion Steam Howto](https://rpmfusion.org/Howto/Steam) — Steam installation guide
- [Fedora Gaming Docs - Gamescope](https://docs.fedoraproject.org/en-US/gaming/gamescope/) — Gamescope documentation
- [MangoHud GitHub](https://github.com/flightlessmango/MangoHud) — Upstream project
- [GameMode GitHub](https://github.com/FeralInteractive/gamemode) — Upstream project
- [UMU-Launcher Releases](https://github.com/Open-Wine-Components/umu-launcher/releases) — RPM downloads
- [Decky Loader Releases](https://github.com/SteamDeckHomebrew/decky-loader/releases) — Binary downloads

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation | Status |
|------|------------|--------|------------|--------|
| Fedora Steam package may have different paths than Ubuntu Steam | Medium | High | Map all Steam paths during T2; use environment variables where possible | ✅ **CLOSED** — Paths mapped: `/usr/bin/steam`, `/usr/bin/gamescope` |
| bubblewrap patch may not apply cleanly to Fedora's bwrap version | Low | Critical | Version-check bwrap during build; fall back to upstream bwrap if needed | ✅ **CLOSED** — Patch applies cleanly to Fedora's bubblewrap |
| Missing 32-bit libraries for Steam runtime | Medium | Critical | Install glibc.i686 and related 32-bit packages explicitly; validate in T1 | ✅ **CLOSED** — dnf handles multilib natively |
| RPM Fusion repos may be unavailable during build | Low | Medium | Cache RPM packages in CI; use mirror URLs in pins.env | Open — Low risk, pins.env uses stable mirror URLs |
| Decky Loader may not be compatible with non-SteamOS environment | Medium | Low | Mark as optional QoL feature; graceful degradation if installation fails | ✅ **CLOSED** — Works with `/home/deck` symlink and container paths |
| Performance tuning sysctls may not be available in container | Medium | Low | Validate each sysctl in smoke tests; skip unavailable tunings with warning | ✅ **MITIGATED** — `launch-comp.sh` applies sysctls with graceful fallback |
| UMU-Launcher RPM may have dependency conflicts | Low | Medium | Test installation in isolated build; document required dependencies | ✅ **CLOSED** — RPM installs cleanly on Fedora 43 |
| Steam's container runtime conflicts with Docker networking | Low | High | Use host network mode; validate Steam runtime pressure-vessel behavior | Open — Requires production validation |

---

## Validation Gates

Each gate must pass before proceeding to the next phase.

### Phase 1: Research (Wave 1)

| Gate | Description | Blocking Tasks | Status |
|------|-------------|----------------|--------|
| G1 | Package availability confirmed for all required components | T1 | ✅ **PASSED** |
| G2 | GoW compatibility surface mapped (bubblewrap patch, paths, patterns) | T2 | ✅ **PASSED** |
| G3 | pins.env schema validated against project conventions | T3 | ✅ **PASSED** |

### Phase 2: Build (Wave 2)

| Gate | Description | Blocking Tasks |
|------|-------------|----------------|
| G4 | Docker build succeeds without errors | T20 |
| G5 | Policy check passes (no floating refs, verified downloads) | T20 |
| G6 | Image size within acceptable bounds (<2GB uncompressed) | T20 |

### Phase 3: Validation (Wave 2)

| Gate | Description | Blocking Tasks |
|------|-------------|----------------|
| G7 | Smoke tests pass (startup, dependencies, Steam launch) | T17 |
| G8 | gamescope initializes correctly | T17 |
| G9 | QoL features installed and functional | T17 |

---

## Decision Log

| Decision | Choice | Rationale | Date | Revisit? |
|----------|--------|-----------|------|----------|
| Base distribution | Fedora 43 | Fedora 43 is current stable | 2026-03-09 | When F44 releases |
| Display server | gamescope-only (no sway) | Scope control; Steam Deck precedent; reduces complexity | 2026-03-09 | No |
| Base image | Fedora official (not base-app) | Fedora native stack differs from Ubuntu; avoid layering issues | 2026-03-09 | If base-app adds Fedora support |
| Game launchers | Steam-only (no Lutris/Heroic) | Scope control; Wolf use case is Steam-centric | 2026-03-09 | Post-MVP if demand exists |
| Target platform | Wolf-first (standalone later) | Primary use case is Wolf streaming; standalone is nice-to-have | 2026-03-09 | Post-MVP |
| Test strategy | Smoke tests only (no integration tests) | Integration tests require full Wolf stack; smoke tests validate container health | 2026-03-09 | No |
| Decky Loader | Included as optional QoL | High value for Steam Deck users; graceful degradation if incompatible | 2026-03-09 | If compatibility issues persist |
| UMU-Launcher | Included via RPM | Better Proton management; Fedora-native package available | 2026-03-09 | No |
| Performance tuning | sysctl-based where available | Minimal risk; container-compatible; documented limitations | 2026-03-09 | No |

---

## Open Questions

All questions resolved during Wave 1 tasks:

1. **Steam path differences**: ✅ **RESOLVED** — RPM Fusion Steam uses `/usr/bin/steam` on Fedora.
2. **32-bit library scope**: ✅ **RESOLVED** — Fedora handles 32-bit/multilib natively via dnf. Steam automatically pulls in required i686 packages.
3. **Decky Loader compatibility**: ✅ **RESOLVED** — PluginLoader binary at `/opt/decky/PluginLoader` works with container paths. `/home/deck` symlink created for SteamOS compatibility.
4. **gamescope MangoApp integration**: ✅ **RESOLVED** — MangoApp is bundled with the `mangohud` package in Fedora repos. Works with gamescope via `STEAM_USE_MANGOAPP=1`.
5. **UMU-Launcher Proton directory**: ✅ **RESOLVED** — UMU-Launcher RPM respects standard Steam paths and `STEAM_COMPAT_DATA_PATH`.

---

## Next Steps

Wave 1 complete. All validation gates passed:
- ✅ G1: Package availability confirmed
- ✅ G2: GoW compatibility surface mapped
- ✅ G3: pins.env schema validated

Wave 2 tasks (T4-T18) complete. Build, smoke tests, and update scripts implemented and passing.

---

*Document finalized 2026-03-09. All open questions resolved, validation gates passed.*
