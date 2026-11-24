#!/usr/bin/env bash
# =============================================================================
#  PROJECT ZENITH — Universal Arch Linux & Derivatives Installer
# =============================================================================
#  Supports: Arch Linux, EndeavourOS, CachyOS, Manjaro, Garuda, ArcoLinux
#  Zero Python requirement. Pure compiled Rust & C + POSIX Shell.
# =============================================================================
set -euo pipefail

# ANSI Styling
bold="\033[1m"
dim="\033[2m"
green="\033[32m"
blue="\033[34m"
yellow="\033[33m"
red="\033[31m"
reset="\033[0m"

log_info()  { printf "%b[INFO]%b  %s\n" "$blue" "$reset" "$*"; }
log_ok()    { printf "%b[OK]%b    %s\n" "$green" "$reset" "$*"; }
log_warn()  { printf "%b[WARN]%b  %s\n" "$yellow" "$reset" "$*"; }
log_err()   { printf "%b[ERROR]%b %s\n" "$red" "$reset" "$*" >&2; }
die()       { log_err "$*"; exit 1; }

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

printf "%b" "$bold$blue"
cat << "EOF"
  ______ _____ _   _ _____ _____ _   _ 
 |___  /|  ___| \ | |_   _|_   _| | | |
    / / | |__ |  \| | | |   | | | |_| |
   / /  |  __|| . ` | | |   | | |  _  |
 ./ /___| |___| |\  |_| |_  | | | | | |
 \_____/\____/\_| \_/\___/  \_/ \_| |_/
EOF
printf "%b\n" "$reset$dim  The Zero-Bloat, Event-Driven Desktop for Hyprland$reset\n"

# 1. Distro Compatibility Verification (Arch + Derivatives)
log_info "Verifying host distribution compatibility..."
if [[ ! -r /etc/os-release ]]; then
    die "/etc/os-release missing; cannot verify Linux distribution."
fi

# shellcheck disable=SC1091
source /etc/os-release
IS_ARCH=false
if [[ "${ID:-}" == "arch" || "${ID_LIKE:-}" =~ arch ]]; then
    IS_ARCH=true
fi

if [[ "$IS_ARCH" != true ]]; then
    die "Zenith requires Arch Linux or an Arch-derivative (detected ID=${ID:-unknown}, ID_LIKE=${ID_LIKE:-none})."
fi
log_ok "Host identified as ${NAME:-Arch Linux} (${ID:-arch})"

# 2. Package Manager & AUR Helper Detection
log_info "Detecting AUR helper..."
AUR_HELPER=""
if command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
elif command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
else
    log_warn "Neither 'paru' nor 'yay' found. Zenith will install yay automatically."
fi

install_yay() {
    log_info "Bootstrapping yay AUR helper..."
    sudo pacman -S --needed --noconfirm base-devel git
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay-bin.git "$tmp_dir/yay-bin"
    (cd "$tmp_dir/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp_dir"
    AUR_HELPER="yay"
    log_ok "yay installed successfully."
}

if [[ -z "$AUR_HELPER" ]]; then
    install_yay
fi
log_ok "Using AUR helper: $AUR_HELPER"

# 3. Core System & Mobile Phone Cable Sharing Dependencies
log_info "Installing core system packages, Hyprland, and phone-cable sharing stack..."

PACMAN_PACKAGES=(
    # Compositor & Wayland core
    hyprland hyprlock hypridle hyprpaper swww
    xorg-xwayland wayland-protocols

    # Default Applications
    foot firefox thunar

    # Phone Cable Sharing & Mobile Integration Stack
    # Core Android MTP stack
    gvfs gvfs-mtp gvfs-gphoto2 android-udev
    thunar-volman tumbler thunar-archive-plugin

    # Shell, Menus & Clipboard
    rofi-wayland cliphist wl-clipboard
    grim slurp swappy jq libnotify fastfetch
    hyprpolkitagent

    # Audio & Hardware
    pipewire pipewire-pulse wireplumber playerctl
    bluez bluez-utils networkmanager brightnessctl

    # C / Rust Build Toolchain & Libraries
    base-devel rust cargo gcc make pkg-config
    gtk4 cairo glib2 json-c imagemagick

    # Fonts
    ttf-jetbrains-mono-nerd ttf-font-awesome noto-fonts-emoji

    # Display Manager (login screen on boot)
    sddm

    # Logout screen & OCR
    wlogout tesseract tesseract-data-eng
)

AUR_PACKAGES=(
    # Quickshell Wayland layer-shell engine
    quickshell
    # VSCodium
    vscodium-bin
    # Icon theme used by rofi app launcher
    tela-circle-icon-theme-dracula
)

log_info "Installing official repository packages..."
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

# Optional Apple iOS stack (non-fatal if pacman encounters issues or user is pure Android)
OPTIONAL_IOS_PACKAGES=(gvfs-afc usbmuxd libimobiledevice)
log_info "Attempting to install optional iOS sharing stack (will skip safely if unavailable)..."
sudo pacman -S --needed --noconfirm "${OPTIONAL_IOS_PACKAGES[@]}" 2>/dev/null || log_warn "iOS sharing packages skipped or unavailable (Android MTP remains fully operational)."

log_info "Installing AUR packages..."
"$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}"

# 4. Service Activation (Phone cable sharing, Bluetooth, Network)
log_info "Configuring system services and socket activation..."
sudo systemctl enable --now NetworkManager.service
sudo systemctl enable --now bluetooth.service

# Socket-activate usbmuxd if installed (zero RAM when no iPhone is plugged in)
if systemctl list-unit-files usbmuxd.socket >/dev/null 2>&1; then
    sudo systemctl enable usbmuxd.socket 2>/dev/null || true
    sudo systemctl start usbmuxd.socket 2>/dev/null || true
fi

log_ok "Services configured."

# Enable SDDM display manager (gives login screen on every boot)
log_info "Enabling SDDM display manager..."
sudo systemctl enable sddm.service
# Register Hyprland as a Wayland session for SDDM if not already present
if [[ ! -f /usr/share/wayland-sessions/hyprland.desktop ]]; then
    sudo mkdir -p /usr/share/wayland-sessions
    sudo tee /usr/share/wayland-sessions/hyprland.desktop > /dev/null << 'DESKTOP'
[Desktop Entry]
Name=Hyprland
Comment=Hyprland Wayland Compositor
Exec=start-hyprland
Type=Application
DESKTOP
fi
log_ok "SDDM enabled — system will show a login screen after every reboot."

# 5. Build Native C & Rust Subsystems
log_info "Building Zenith native C & Rust components..."
mkdir -p "$ROOT_DIR/build"

# 5.1 Compile 0ms C Dispatcher (zenith-ctl)
log_info "Compiling zenith-ctl (0ms PID toggle dispatcher)..."
gcc -O3 -Wall -Wextra "$ROOT_DIR/native/zenith-ctl.c" -o "$ROOT_DIR/build/zenith-ctl"
chmod +x "$ROOT_DIR/build/zenith-ctl"
log_ok "zenith-ctl compiled successfully."

# 5.2 Compile C Cinematic Wallpaper Gallery
log_info "Compiling wallpaper gallery..."
if [[ -f "$ROOT_DIR/native/gallery.c" ]]; then
    gcc -O3 -Wall -Wextra "$ROOT_DIR/native/gallery.c" \
        $(pkg-config --cflags --libs gtk4 cairo json-c) \
        -lm -o "$ROOT_DIR/build/gallery"
    chmod +x "$ROOT_DIR/build/gallery"
    log_ok "gallery compiled successfully."
fi

# 5.3 Compile Rust Native Helper (zenith-native)
if [[ -f "$ROOT_DIR/native/Cargo.toml" ]]; then
    log_info "Compiling zenith-native (Rust geometry & theme engine)..."
    (cd "$ROOT_DIR/native" && cargo build --release)
    cp -f "$ROOT_DIR/native/target/release/zenith-native" "$ROOT_DIR/build/zenith-native"
    chmod +x "$ROOT_DIR/build/zenith-native"
    log_ok "zenith-native compiled successfully."
fi

# 6. User Config Directory Deployment
log_info "Deploying Zenith user configuration..."
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$CONFIG_HOME/hypr" "$CONFIG_HOME/foot" "$CONFIG_HOME/zenith"

# Backup existing hyprland config if present
if [[ -f "$CONFIG_HOME/hypr/hyprland.conf" || -f "$CONFIG_HOME/hypr/hyprland.lua" ]]; then
    backup_date="$(date +%Y%m%d_%H%M%S)"
    log_warn "Backing up existing Hyprland config to $CONFIG_HOME/hypr.backup.$backup_date"
    mv "$CONFIG_HOME/hypr" "$CONFIG_HOME/hypr.backup.$backup_date"
    mkdir -p "$CONFIG_HOME/hypr"
fi

# Write ZENITH_ROOT so paths.lua always resolves the correct repo root
mkdir -p "$CONFIG_HOME/zenith"
printf '%s\n' "$ROOT_DIR" > "$CONFIG_HOME/zenith/root"
log_ok "ZENITH_ROOT written to $CONFIG_HOME/zenith/root -> $ROOT_DIR"

# Symlink or Copy Hyprland Lua modules
cp -rf "$ROOT_DIR/hypr/"* "$CONFIG_HOME/hypr/"
log_ok "Hyprland Lua modules deployed to $CONFIG_HOME/hypr/"

# User scripts — make all scripts in scripts/ executable
chmod +x "$ROOT_DIR/scripts/"*.sh

# hypridle + hyprlock configs
ln -sf "$ROOT_DIR/hypr/hyprlock.conf"  "$HOME/.config/hypr/hyprlock.conf"
ln -sf "$ROOT_DIR/hypr/hypridle.conf"  "$HOME/.config/hypr/hypridle.conf"

# Avatar placeholder (user replaces with their own)
AVATAR_DIR="$HOME/.config/zenith/assets"
mkdir -p "$AVATAR_DIR"
[ -f "$AVATAR_DIR/avatar.png" ] || cp "$ROOT_DIR/assets/avatar.png" "$AVATAR_DIR/avatar.png" 2>/dev/null || \
  magick -size 84x84 xc:'#59b9e8' -fill white -font JetBrainsMono-NF -pointsize 36 \
  -gravity center -annotate 0 'Z' "$AVATAR_DIR/avatar.png" 2>/dev/null || true

# Foot configuration
mkdir -p "$CONFIG_HOME/foot"
if [[ -f "$ROOT_DIR/foot/foot.ini" ]]; then
    cp -f "$ROOT_DIR/foot/foot.ini" "$CONFIG_HOME/foot/foot.ini"
fi

# Deploy Fastfetch & Minimal Arrow Prompt
mkdir -p "$CONFIG_HOME/zenith/fastfetch"
cp -rf "$ROOT_DIR/fastfetch/"* "$CONFIG_HOME/zenith/fastfetch/" 2>/dev/null || true

# Pre-populate theme override and state so rofi & quickshell parse cleanly on first launch
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$CACHE_HOME/zenith" "$STATE_HOME/zenith" "$CONFIG_HOME/foot"
touch "$CACHE_HOME/zenith/theme-override.rasi"

# Copy default foot colors into place
if [[ -f "$ROOT_DIR/foot/colors.ini" && ! -f "$CONFIG_HOME/foot/colors.ini" ]]; then
    cp -f "$ROOT_DIR/foot/colors.ini" "$CONFIG_HOME/foot/colors.ini"
fi

# Deploy default palette
if [[ -f "$ROOT_DIR/generated/palette.json" ]]; then
    cp -f "$ROOT_DIR/generated/palette.json" "$STATE_HOME/zenith/palette.json"
fi

# Ensure default settings are seeded on first install so Island is never dormant/hidden by default
if [[ ! -f "$STATE_HOME/zenith/settings.json" ]]; then
    cat << 'EOF' > "$STATE_HOME/zenith/settings.json"
{
  "appearance": {
    "mode": "dark",
    "material": "solid",
    "surfaceOpacity": 0.96,
    "islandStyle": "floating",
    "wallpaperPaletteEnabled": true
  },
  "island": {
    "topMargin": 5,
    "reservedSpace": 30,
    "dormantWidth": 214,
    "autoHide": false,
    "showRevealLip": true,
    "borderEnabled": true
  },
  "displays": {
    "islandPolicy": "all",
    "primaryMonitor": "auto"
  }
}
EOF
fi

# Pre-generate 1:1 wallpaper crops and cache if wallpapers exist and binaries are built
if [[ -x "$ROOT_DIR/build/zenith-native" ]]; then
    log_info "Bootstrapping initial wallpaper, blur cache, and color palette..."
    INIT_WALL="$(find "$ROOT_DIR/wallpapers" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | head -1 || true)"
    if [[ -n "$INIT_WALL" && -r "$INIT_WALL" ]]; then
        printf '%s\n' "$INIT_WALL" > "$STATE_HOME/zenith/current_wallpaper"
        "$ROOT_DIR/build/zenith-native" align 2>/dev/null || true
        "$ROOT_DIR/build/zenith-native" theme 2>/dev/null || true
        log_ok "Initial wallpaper theme & crops generated."
    fi
fi

if [[ -f "$HOME/.bashrc" ]] && ! grep -q "zenith/scripts/prompt.sh" "$HOME/.bashrc"; then
    printf '\n# Project Zenith Minimal Arrow Prompt\n[ -f "%s/scripts/prompt.sh" ] && source "%s/scripts/prompt.sh"\n' "$ROOT_DIR" "$ROOT_DIR" >> "$HOME/.bashrc"
fi

# 7. Hyprland Auto-Start Configuration (Auto-launch from TTY1)
log_info "Configuring automatic Hyprland startup from TTY..."

# Determine optimal launcher binary (start-hyprland wrapper initializes environment & systemd)
LAUNCH_CMD="Hyprland"
if command -v start-hyprland >/dev/null 2>&1; then
    LAUNCH_CMD="start-hyprland"
fi

TTY_HYPRLAND_SNIPPET='
# Auto-start Hyprland on TTY1 login if not already in graphical session
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ] && [ -z "$WAYLAND_DISPLAY" ]; then
    if command -v start-hyprland >/dev/null 2>&1; then
        exec start-hyprland
    else
        exec Hyprland
    fi
fi'

# Configure user profile scripts (~/.bash_profile or ~/.profile or ~/.zprofile)
TARGET_PROFILE=""
if [[ -f "$HOME/.bash_profile" ]]; then
    TARGET_PROFILE="$HOME/.bash_profile"
elif [[ -f "$HOME/.zprofile" ]]; then
    TARGET_PROFILE="$HOME/.zprofile"
elif [[ -f "$HOME/.profile" ]]; then
    TARGET_PROFILE="$HOME/.profile"
else
    TARGET_PROFILE="$HOME/.bash_profile"
    touch "$TARGET_PROFILE"
fi

if ! grep -q "start-hyprland" "$TARGET_PROFILE" 2>/dev/null && ! grep -q "exec Hyprland" "$TARGET_PROFILE" 2>/dev/null; then
    printf "\n%s\n" "$TTY_HYPRLAND_SNIPPET" >> "$TARGET_PROFILE"
    log_ok "Configured Hyprland auto-start in $TARGET_PROFILE"
fi

# If using ~/.bashrc in login shell environments, ensure profile is sourced or checked
if [[ -f "$HOME/.bashrc" ]] && ! grep -q "start-hyprland" "$HOME/.bashrc" && ! grep -q "exec Hyprland" "$HOME/.bashrc"; then
    # Add non-intrusive TTY1 autostart check
    printf "\n# Auto-start Hyprland on TTY1 login\nif [[ -z \"\$DISPLAY\" ]] && [[ \"\$(tty 2>/dev/null)\" == \"/dev/tty1\" ]] && [[ -z \"\$WAYLAND_DISPLAY\" ]]; then\n    if command -v start-hyprland >/dev/null 2>&1; then\n        exec start-hyprland\n    else\n        exec Hyprland\n    fi\nfi\n" >> "$HOME/.bashrc"
fi

# Enable Foot server user service for sub-millisecond terminal launches
systemctl --user enable --now foot-server.service 2>/dev/null || true

printf "\n%b" "$bold$green"
cat << "EOF"
  ======================================================
     PROJECT ZENITH INSTALLATION COMPLETED SUCCESSFULLY!
  ======================================================
EOF
printf "%b\n" "$reset"
printf "  • Launch with: %b%s%b (or login on TTY1 to auto-launch)\n" "$bold$blue" "$LAUNCH_CMD" "$reset"
printf "  • App Launcher: %bSUPER + A%b (0ms instant pop-in)\n" "$bold$green" "$reset"
printf "  • Clipboard:    %bSUPER + C%b (Anchored top-right)\n" "$bold$green" "$reset"
printf "  • Wallpaper:    %bSUPER + W%b (Cinematic Wallpaper Shower)\n" "$bold$green" "$reset"
printf "  • Codium:       %bSUPER + O%b\n" "$bold$green" "$reset"
printf "  • Phone Sharing:%bPlug in Android (MTP) to Thunar%b\n\n" "$bold$yellow" "$reset"

# Ask or automatically transition to Hyprland if currently in a TTY session
if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
    printf "%bZenith installation finished!%b Launching Hyprland now...\n" "$bold$green" "$reset"
    read -r -t 5 -p "Starting in 5 seconds (Press Enter to start immediately, or Ctrl+C to stay in shell)... " || true
    echo ""
    if command -v start-hyprland >/dev/null 2>&1; then
        exec start-hyprland
    else
        exec Hyprland
    fi
fi
