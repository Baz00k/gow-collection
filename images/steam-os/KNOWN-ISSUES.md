# SteamOS Known Issues

Problems you may run into with the [SteamOS image](README.md), and what to do about them.

## Gaming Mode

### Steam's UI is laggy

Menus and the overlay stutter while games run fine.
In desktop mode, open Steam, go to Settings, and enable GPU accelerated rendering in web views.

### Game uses only a few CPU threads

Low FPS while the GPU is underused and only a few CPU cores are busy.
Add `gamemoderun %command%` to the game's Steam launch options.

### MangoHud stats freeze or look wrong

MangoHud runs as MangoApp through gamescope, so FPS stats can freeze or show wrong values while the game runs normally. There is no fix yet.

### Non-Steam game stays behind Steam's loading screen

Flatpak launchers such as Heroic start games outside Steam's process tree, so Steam can't match the window to its shortcut. umu tags it, but only on gamescope's separate game display.
Don't pass `--xwayland-count 1` in `GAMESCOPE_EXTRA_ARGS`.

### Mouse spins the camera or does nothing in menus

Gamescope runs nested inside Wolf and must grab the cursor to pass raw mouse input to games.
The image does this by default (`GAMESCOPE_FORCE_GRAB_CURSOR=on`). Keep it on.

## Desktop Mode

### Games run worse than in gaming mode

Add non-Steam games to Steam and launch them from gaming mode.

### Trying Wine's Wayland driver

Proton games use X11 in both gaming and desktop mode, and some games crash on Wine's Wayland driver.
To try it for a game, set its launch options to `PROTON_ENABLE_WAYLAND=1 %command%`.

### Plasma behaves differently from a Steam Deck

KDE Plasma runs nested inside Wolf's compositor, so some compositor behavior differs from a physical Steam Deck.

## Container Limits

- Flatpak app installs depend on the container permissions and namespace support provided by the Wolf runner configuration.
- SteamOS update, BIOS update, and hardware power-management commands are compatibility stubs, not real host firmware or OS controls.
