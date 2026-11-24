# 🌌 Project Zenith

> **The Zero-Bloat, Event-Driven, Hardware-Aware Hyprland Desktop Environment**  
> Powered by Quickshell Dynamic Island, Dual-Pane Rofi, Native C/Rust Geometry Engine, and the Cinematic Wallpaper Shower.

---

## ⚡ Core Philosophy & Standards

1. **Sub-Millisecond Responsiveness (0ms Perceived Latency):**  
   Hot-path application and clipboard launches bypass bash/subshell forks via `zenith-ctl` (compiled C PID dispatcher) directly mapping to the next monitor VBlank.
2. **True Zero-Idle Overhead:**  
   Variable Frame Rate (`vfr = true`) draws **0 FPS** when the screen is static. Client-server terminal pooling (`foot --server`) keeps terminal RAM under 3 MB per instance.
3. **Cinematic Wallpaper Shower:**  
   A widescreen 70/30 gallery combining a massive high-res hero preview on top with an interactive 16:9 filmstrip dock along the bottom.
4. **Mathematical 1:1 Wallpaper Alignment:**  
   Pixel-accurate wallpaper cropping engine written in Rust compensating for viewport scale, monitor offsets, and Rofi dimensions with **0-subpixel drift**.
5. **Universal Portability:**  
   Seamless support for Arch Linux, EndeavourOS, CachyOS, Manjaro, Garuda, and ArcoLinux.
6. **Strict Zero-Python Standard:**  
   100% compiled C, Rust, and POSIX shell. No Python runtime dependencies.

---

## ⌨️ Conflict-Free Keybindings

| Key Combination | Action | Subsystem |
| :--- | :--- | :--- |
| `SUPER + T` | Terminal | `footclient` (instant sub-2ms launch) |
| `SUPER + A` | Application Launcher | 0ms Dual-Pane Rofi |
| `SUPER + Tab` | Window Switcher | Rofi Window Selector |
| `SUPER + C` | Clipboard Manager | Anchored Top-Right Rofi |
| `SUPER + SHIFT + C`| Wipe Clipboard History | `cliphist wipe` |
| `SUPER + E` | File Manager | `thunar` (with Android MTP & iPhone AFC sharing) |
| `SUPER + B` | Web Browser | `firefox` |
| `SUPER + O` | Code Editor | `codium` / `code` |
| `SUPER + W` | Wallpaper Shower | Cinematic Widescreen Gallery (`gallery.c`) |
| `SUPER + SHIFT + W`| Random Wallpaper | `zenith-native wallpaper random` |
| `SUPER + N` | Island Control Center | Dynamic Island Hardware Panel (WiFi / Bluetooth) |
| `SUPER + Q` | Close Window | Hyprland Dispatcher |
| `SUPER + M` | Fullscreen Toggle | Hyprland Dispatcher |
| `SUPER + SHIFT + F`| Floating Mode Toggle | Hyprland Dispatcher |
| `SUPER + [1-9]` | Switch Workspace | Hyprland Workspaces 1–9 |
| `SUPER + BackSpace`| Pocket Dimension | Special Scratchpad Workspace |
| `SUPER + L` | Lock Screen | `hyprlock` |
| `SUPER + Escape` | Power Menu | Island Session Screen |
| `Print` | Region Screenshot | `grim` + `slurp` -> Clipboard |
| `SHIFT + Print` | Annotate Screenshot | `grim` + `slurp` -> `swappy` |
| `SUPER + SHIFT + O`| Region OCR | `grim` + `tesseract` -> Clipboard |

---

## 🛠️ Directory Structure

```
zenith/
├── hypr/               # Modular Hyprland Lua Configuration (Single Responsibility)
│   ├── hyprland.lua    # Master loader & cache invalidator
│   ├── paths.lua       # Filesystem & XDG path resolution
│   ├── monitors.lua    # Hardware-agnostic monitor setup
│   ├── hardware.lua    # Input gestures, touchpad, mouse speed
│   ├── autostart.lua   # Daemons & background services
│   ├── looknfeel.lua   # VFR, VRR, explicit sync, direct scanout, 2-pass blur
│   ├── keybinds.lua    # Deduplicated keybindings matrix
│   ├── rules.lua       # 0ms layer rules & floating window rules
│   └── colors.lua      # Dynamic palette variables
├── native/             # Compiled C & Rust Subsystems (Zero Python)
│   ├── Cargo.toml      # Optimized LTO Rust build configuration
│   ├── zenith-ctl.c    # Sub-millisecond C toggle dispatcher
│   ├── gallery.c       # Cinematic 70/30 wallpaper gallery
│   └── src/            # Rust source: geometry, theme, wallpaper, clipboard
├── island/             # Quickshell Dynamic Island (Decoupled, zero launcher/clipboard)
├── services/           # Quickshell Network & Bluetooth singletons
├── rofi/               # Wallpaper-aligned Dual-Pane Launcher & Clipboard
├── foot/               # Ultra-low latency terminal configuration
├── wallpapers/         # Curated wallpaper collections
├── scripts/            # Check & utility scripts
├── install.sh          # Universal Arch/Derivative Installer
└── PLAN.md             # Complete architectural specification & Spiral Model
```

---

## 🚀 Installation

Run the idempotent installer on any Arch-based distribution:

```bash
chmod +x install.sh
./install.sh
```
