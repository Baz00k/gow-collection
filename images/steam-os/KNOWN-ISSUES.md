# SteamOS Known Issues

Problems you may run into with the [SteamOS image](README.md), and what to do about them.

## Gaming Mode

### Mouse spins the camera or does nothing in menus

Gamescope runs nested inside Wolf, so it has to capture the mouse itself to pass on real mouse movement.
The image does this by default (`GAMESCOPE_FORCE_GRAB_CURSOR=on`).
With it off, games that read raw mouse input, like The Witcher 3, ignore the mouse in menus and spin the camera in game.

### Non-Steam game stays behind Steam's loading screen

Some non-Steam launchers start games whose windows keep `steam_app_0` instead of the active Steam AppId, and gamescope leaves them behind the loading screen.
A small helper tags those windows with the right AppId (`STEAM_WINDOW_TAGGER=on`).
Set `STEAM_WINDOW_TAGGER=off` if it causes problems or you want unmodified Steam/gamescope behavior.

### Steam's UI is laggy

Enable Steam GPU acceleration from desktop mode: switch to KDE Plasma, open Steam, go to Settings, and enable GPU accelerated rendering in web views.

### Game uses only a few CPU threads

Some games only use a few CPU threads unless launched through GameMode. Add `gamemoderun %command%` to the game's Steam launch options.

### MangoHud stats freeze or look wrong

MangoHud runs as MangoApp through gamescope. FPS stats may freeze or show wrong values even when the game is running normally.

### Modifier keys are not held during gameplay

Gamescope can lose keyboard modifier state in nested Wayland sessions. Affected games detect Left Shift or Control while rebinding, but do not see the modifier held during gameplay.
This is tracked upstream in [gamescope #2032](https://github.com/ValveSoftware/gamescope/issues/2032) and the underlying nested-modifier issue [gamescope #266](https://github.com/ValveSoftware/gamescope/issues/266). The same symptom was previously reported to Wolf in [wolf #217](https://github.com/games-on-whales/wolf/issues/217).

## Desktop Mode

### Games run worse than in gaming mode

Gaming performance in desktop mode can be noticeably worse for some games. Add non-Steam games to Steam and launch them from gaming mode.

### Trying Wine's Wayland driver

Proton games use X11 in both sessions. Some games crash on Wine's Wayland driver, such as The Binding of Isaac, which closes right after launch.
To try it for a game in desktop mode anyway, set its launch options to `PROTON_ENABLE_WAYLAND=1 %command%`.

### Plasma behaves differently from a Steam Deck

KDE Plasma runs nested inside Wolf's compositor, so some desktop compositor behavior differs from a physical Steam Deck.

## Container Limits

- Flatpak app installs depend on the container permissions and namespace support provided by the Wolf runner configuration.
- SteamOS update, BIOS update, and hardware power-management commands are compatibility stubs, not real host firmware or OS controls.
