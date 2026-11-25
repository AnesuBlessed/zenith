# Project Zenith — Architecture & Build Plan

Zenith is a Hyprland desktop built from five layers:

1. **Hyprland Lua modules** (`hypr/`) — compositor rules, keybinds, autostart.
2. **Quickshell island** (`shell.qml`, `island/`, `panels/`, `components/`) — QML UI.
3. **Native engine** (`native/`) — Rust owns wallpapers, palettes, thumbnails,
   clipboard scripting and the notification presentation stack; C dispatches
   rofi/picker by PID and forwards notification commands over a Unix socket.
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

## Notification presentation

Quickshell still owns the freedesktop D-Bus `NotificationServer`, history,
actions and DND. Presentation is native: `NotificationBridge.qml` forwards the
active popup entries through `zenith-notifyctl` (C) to `zenith-native notify
daemon` (Rust). The Rust engine keeps a bounded, spring-animated stack with
hover freezing and timeout expiry, and publishes an atomic JSON snapshot.
`island/NotifyStack.qml` renders that snapshot on the existing island surface;
the old single-card `IslandNotification.qml` is gone.

## Lock and greeter presentation

`hyprlock.conf` and `sddm/zenith/Main.qml` are two renderers of one contract.
The native wallpaper transaction writes the processed background and avatar to
`$HOME/.cache/zenith` and mirrors them into `/var/lib/zenith`, where the SDDM
user can read them. Palette tokens are written to the same shared directory as
a small QML object, and `scripts/lock-status.sh snapshot` publishes the status
strings both screens display. The SDDM theme declares `QtVersion=6` and uses
`sessionModel.lastIndex`, `userModel.lastUser` and integer-index
`sddm.login()`, so it no longer falls back to the embedded greeter.

The greeter layout is SilentSDDM-inspired — centered glass login card, avatar,
user/password/login pill, bottom session and power popups — but all text uses
`Zenith Display` (Nerd font only for status glyphs), and no SilentSDDM code or
assets are vendored. The card reads only Zenith's generated artifacts.

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
