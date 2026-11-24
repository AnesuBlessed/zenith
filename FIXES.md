# Project Zenith — Fixes & Change Log

Comprehensive summary of all issues resolved, configurations modernized, and enhancements pushed to Project Zenith during setup, hardware auditing, and testbed deployment.

---

## 1. High-Level Summary of Issues & Root Causes

| Subsystem | Symptoms / Issue | Root Cause | Solution Implemented |
|---|---|---|---|
| **Display Manager** | System booted straight into raw TTY after rebooting | `sddm` package was not installed or enabled in `install.sh` | Added `sddm` to `PACMAN_PACKAGES`, enabled `sddm.service`, and created `/usr/share/wayland-sessions/hyprland.desktop`. |
| **Compositor Startup** | Black screen on boot; no wallpaper | `swww-daemon` was running but no initial `swww img` call was executed; wallpaper helper was absent | Added an auto-wallpaper initialization trigger in `autostart.lua` and built `scripts/wallpaperctl.sh`. |
| **Dynamic Island (Quickshell)** | Island was missing / not rendering | Missing helper scripts (`wallpaperctl.sh`, `notesctl.sh`, `notification-provenance.sh`), incorrect `ZENITH_ROOT` path resolution, and layer shell namespace mismatch (`zenith:island` vs `quickshell`) | Built missing scripts in pure POSIX shell, exported `~/.config/zenith/root`, updated layer rules in `rules.lua` to match `zenith:island*`. |
| **App Launcher & Clipboard** | `Super + A` and `Super + C` did not trigger Rofi | `zenith-ctl` looked for `.rasi` files in `~/.config/zenith` instead of repository root, and `~/.cache/zenith/theme-override.rasi` was missing | Patched `zenith-ctl.c` to parse `~/.config/zenith/root`, pre-created `theme-override.rasi` in `install.sh`, and added icon themes. |
| **Hyprland 0.55+ Lua Engine** | Red error banner on screen with syntax and deprecated keys | Deprecated `render.explicit_sync`, table syntax error in `hardware.lua`, outdated gestures syntax, non-existent `hl.exec_once` | Modernized Hyprland Lua API calls (`hl.on("hyprland.start", ...)`, `hl.gesture()`, `no_anim`). |
| **Zero-Python Compliance** | QML files attempted to run Python helpers that were missing or violated zero-Python architecture | QML services referenced `.py` files | Replaced all helper scripts with 100% POSIX shell scripts (`notesctl.sh`, `notification-provenance.sh`). |
| **Mobile Integration** | Install failed on Apple iOS packages for Android-only users | Strict pacman install on optional Apple tools | Made iOS stack (`gvfs-afc`, `usbmuxd`, `libimobiledevice`) optional and non-fatal while preserving full Android MTP support. |

---

## 2. Commit History & Detailed Breakdown

### Commit `b41b8ca`
**`fix(desktop): add wallpaperctl script, update island layer rules, fix foot bind, and resolve rofi/zenith-ctl paths`**
- **Created `scripts/wallpaperctl.sh`**:
  - Implemented pure POSIX shell helper for Quickshell's `WallpaperService.qml`.
  - Supports `probe`, `bootstrap`, `list`, `render`, and `apply` commands using `swww`.
- **Updated `hypr/rules.lua`**:
  - Adjusted `quickshell_island` layer rule namespace match to:
    `^(quickshell|zenith:island|zenith:island:glass)$`
- **Patched `native/zenith-ctl.c`**:
  - Added reading of `~/.config/zenith/root` in `get_zenith_root()` so Rofi themes and scripts correctly resolve from the workspace.
- **Updated `install.sh`**:
  - Pre-creates `~/.cache/zenith/theme-override.rasi` to avoid Rofi import parse errors on clean installations.
  - Added executable permissions for `wallpaperctl.sh`.
- **Updated `hypr/keybinds.lua`**:
  - Simplified terminal keybind `Super + T` to directly execute `foot`.

---

### Commit `04d22d3`
**`fix(audit): add missing scripts, replace Python with shell, add wlogout/tesseract/icon-theme packages`**
- **Created `scripts/clipboardctl.sh`**:
  - Provides `copy`, `delete`, `wipe`, and `list` operations wrapping `cliphist` and `wl-copy`.
- **Created `scripts/notesctl.sh`**:
  - Implemented full JSON-based CRUD note storage in pure POSIX shell without Python.
  - Updated `services/NotesService.qml` to point to `notesctl.sh`.
- **Created `scripts/notification-provenance.sh`**:
  - Pure shell process tracking via `/proc/<pid>/exe` and `/proc/<pid>/comm`.
  - Updated `services/NotificationService.qml` to invoke `bash` instead of `python3`.
- **Updated `install.sh`**:
  - Added `wlogout` (session exit dialog for `Super + Escape`).
  - Added `tesseract` and `tesseract-data-eng` (OCR screen capture for `Super + Shift + O`).
  - Added `tela-circle-icon-theme-dracula` to `AUR_PACKAGES` for Rofi icons.

---

### Commit `884853a`
**`fix: SDDM login screen, wallpaper on boot, correct ZENITH_ROOT path, and polkit shell fix`**
- **SDDM Integration**:
  - Added `sddm` to `PACMAN_PACKAGES`.
  - Enabled `sddm.service` via `systemctl enable`.
  - Registered `/usr/share/wayland-sessions/hyprland.desktop` for Wayland session discovery.
- **Root Resolution in `hypr/paths.lua`**:
  - Primary resolution now reads `~/.config/zenith/root` created at install time, ensuring `paths.root` accurately points to `~/zenith` rather than `~/.config`.
- **Wallpaper On First Boot**:
  - Added delayed `swww img` execution in `hypr/autostart.lua` targeting wallpapers from `wallpapers/`.
- **Polkit Agent Fix**:
  - Wrapped authentication agent fallback in `bash -c '...'` so `||` is evaluated by a shell.

---

### Commit `84a74ec`
**`fix(hypr): use start-hyprland wrapper, modern gestures syntax, and no_anim layer rule`**
- **Hyprland Launcher Wrapper**:
  - Updated TTY profile hooks and post-install triggers to prefer `start-hyprland` over bare `Hyprland`.
- **Gestures Modernization**:
  - Replaced legacy `gestures { workspace_swipe = true }` block in `hypr/hardware.lua` with modern `hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })`.
- **Layer Rule Field Fix**:
  - Fixed `noanim` typo to `no_anim` in `hypr/rules.lua`.
- **Notification Cleanup**:
  - Removed obsolete `mako` layer rule references (Quickshell dynamic island exclusively manages notifications).

---

### Commit `ab5f70d`
**`fix(hypr): resolve Lua syntax errors and modernize Hyprland 0.55+ API calls`**
- **Autostart Events**:
  - Replaced undefined `hl.exec_once()` with `hl.on("hyprland.start", function() ... end)`.
- **Table Key Syntax**:
  - Replaced `tap-to-click = true` with `tap_to_click = true` in `hypr/hardware.lua`.
- **Deprecated Render Keys**:
  - Removed `render.explicit_sync = 2` (obsolete in newer Hyprland releases).
- **Daemon Deduplication**:
  - Removed `mako` daemon startup from `autostart.lua`.

---

### Commit `97e9950`
**`fix(installer): make iOS stack optional, auto-launch Hyprland on TTY1, and add missing packages`**
- Separated `gvfs-afc`, `usbmuxd`, and `libimobiledevice` into an optional non-blocking step.
- Added `hyprpolkitagent`, `fastfetch`, and `imagemagick` to system packages.
- Added automated TTY1 graphical login auto-start logic to `~/.bash_profile` and `~/.bashrc`.
- Added tracked lock assets: `assets/avatar.png`, `hypr/hypridle.conf`, `hypr/hyprlock.conf`, and `scripts/lock*.sh`.

---

## 3. Current Architecture Checklist

- [x] **Zero-Python Guarantee:** All daemons, dispatchers, and helpers are compiled C/Rust or pure POSIX shell.
- [x] **Wayland Session Management:** SDDM display manager installed, enabled, and configured with Hyprland desktop entry.
- [x] **Compositor Engine:** Native Hyprland 0.55+ Lua configuration with zero syntax/key errors.
- [x] **Layer Shell Interface:** Quickshell Dynamic Island with complete helper scripts and proper layer rules.
- [x] **Fast App Launcher:** Instant C `zenith-ctl` dispatcher coupled with pixel-aligned dual-pane Rofi.
- [x] **Terminal Client:** Lightweight `foot` terminal configured with fast prompt and ASCII branding.
