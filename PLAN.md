# Project Zenith — Architecture & Build Plan

Zenith is a Hyprland desktop built from five layers:

1. **Hyprland Lua modules** (`hypr/`) — compositor rules, keybinds, autostart.
2. **Quickshell island** (`shell.qml`, `island/`, `panels/`, `components/`) — QML UI.
3. **Native engine** (`native/`) — Rust owns wallpapers, palettes, thumbnails,
   clipboard scripting; C dispatches rofi/picker by PID.
4. **Standalone picker** (`picker/`) — hyprquickpaper layouts ported to QML and
   the Zenith palette; no Python, no web runtime.
5. **Shell helpers** (`scripts/`) — narrow, testable glue for capture, idle,
   session, clipboard, shortcuts and theme exports.

## Wallpaper transaction

`zenith-native wallpaper set <path>` canonicalises the path and performs one
transaction:

- images → `swww img`; videos → `mpvpaper` (requires the optional package);
- a still frame is extracted for hyprlock and launcher crops;
- the seed is extracted from the image and `palette.json` is written with both
  `dark` and `light` token sets;
- Hyprland `colors.lua`, foot colours and the rofi override are regenerated;
- the state files (`current_wallpaper`, `current_wallpaper_image`) are written;
- Hyprland is reloaded and a notification is sent.

The command prints `STATE=`, `COMMITTED=` and `PALETTE=` lines. QML only
treats the selection as committed when those lines report success.

## Picker

`SUPER + W` → `zenith-ctl toggle picker` → `quickshell -p <root>/picker`.
`picker/shell.qml` reads `picker/config.json` and loads the selected layout on
every monitor. Layouts call `Zn.generateThumbs()` and then
`Zn.apply(path)`; the latter uses `Quickshell.execDetached` so the wallpaper
transaction survives the picker closing.

Native thumbnails and the flat symlink index live under
`$XDG_CACHE_HOME/zenith/{thumbs,picker}`. The index exists because bundled
wallpapers are grouped in subdirectories and QML's `FolderListModel` does not
recurse. `wallpaper ensure` warms the cache at login.

## Settings and palette contracts

- `$XDG_CONFIG_HOME/zenith/settings.json` is a flat map of sections
  (`appearance`, `island`, `wallpaper`, `shortcuts`, `idle`, …).
- `$XDG_STATE_HOME/zenith/palette.json` has `mode`, `seed`, `scheme`,
  `dark` and `light`; each mode contains the 16 Zenith tokens.
- Missing files fall back to built-in default palettes in `core/Theme.qml`
  and default values in `core/Config.qml`.

## Build and verify

```bash
./install.sh          # packages, C + Rust builds, deploy, verify
./scripts/check.sh    # zero-Python, Lua, sources, tools, artefacts
```

`install.sh` requires an Arch-family host and a normal desktop user (not root).
The native build needs `gcc`, `rust`/`cargo` and the `image` crate's system-free
codecs; `jq`/ImageMagick are only needed by shell export helpers.
