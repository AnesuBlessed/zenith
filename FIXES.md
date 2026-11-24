# Project Zenith — Fix Log

This file records the current, verified architecture and the defects that were
fixed while bringing the repository to a fresh-install-ready state. Historical
commit notes were removed because they described scripts (wallpaperctl.sh,
notesctl.sh, the C gallery) that no longer exist.

## Current single sources of truth

| Concern | Owner |
| --- | --- |
| Wallpaper + palette transaction | `native/src/wallpaper.rs`, `palette.rs` |
| Picker index + thumbnails | `native/src/thumbs.rs` |
| Launcher / clipboard / picker dispatch | `native/zenith-ctl.c` |
| Settings | `$XDG_CONFIG_HOME/zenith/settings.json` (flat section map) |
| Palette document | `$XDG_STATE_HOME/zenith/palette.json` (`dark` + `light`) |
| Picker UI | `picker/shell.qml` + `picker/layouts/*.qml` |
| Island services | `services/*.qml` + matching `scripts/*.sh` helpers |

## Defects fixed

- Installer now refuses root, installs `lua` for verification, validates the
  picker entrypoint before launching it, and seeds a flat settings file that
  matches `SettingsStore` and the native config reader.
- `shortcutctl.sh` screenshot binding passes the required output mode;
  `SUPER + SHIFT + N` is bound by default so notifications work before managed
  shortcuts are enabled.
- `export-theme.sh` strips `#` correctly before emitting RGB values.
- Scheme changes are written to settings **before** palette regeneration, so the
  generated palette actually uses the selected Material scheme; failures revert
  the preference.
- `wallpaper align` uses the video still frame instead of trying to decode a
  video container.
- Picker thumbnails de-duplicate names by stem, so `foo.jpg` and `foo.mp4` can
  no longer overwrite one another; the flat symlink index is repaired on every
  thumbnail pass and warmed by `wallpaper set`/login. The active wallpaper is
  recorded in `cache/zenith/picker/.current`, so highlighting compares the same
  flat symlink path the picker displays instead of the canonical state path.
- Every picker layout preloads `.current`; without preload the first frame read
  the file before `FileView` populated it and no card was marked active.
- Videos are indexed only when `mpvpaper` is installed, and all catalogues
  share the same video-extension list. This prevents a picker tile that always
  fails on a fresh install without the optional backend.
- Optional AUR extras are installed best-effort, so one unavailable theme or
  editor package can no longer abort the whole install.
- Theme mode changes now regenerate the exported palette (foot/rofi/Hyprlock),
  not just the shell. The old non-functional `Auto` option was removed instead
  of leaving a control that always resolved to dark.
- Picker layout windows are assigned to the screen that created them.
- The picker applies wallpapers through a detached `zenith-native` process, so
  `Qt.quit()` cannot cancel the swww/palette transaction.
- `capturectl.sh` copy-only screenshots reuse a cache path instead of leaking a
  new temporary file.
- Clipboard delete/copy handling is exact-id based; helper command contracts
  match their QML callers.
- Hyprland root discovery tolerates an empty receipt; generated shortcuts use
  the same quote helper as the base keybinds.
- `zenith-ctl` validates a reused PID against `/proc/<pid>/comm`, so a
  recycled PID cannot make `toggle` kill an unrelated process.
- Gallery removal: `native/gallery.c`, the gallery window rule, and the
  in-island wallpaper route are gone. `SUPER + W` opens the standalone picker.

## Verification

Run `./scripts/check.sh` after installing. It enforces zero Python files,
checks the Lua modules, verifies the picker/native sources, and reports missing
runtime tools or build artefacts.