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

    # Phone Cable Sharing & Mobile Integration Stack (Android MTP + Apple iOS AFC)
    gvfs gvfs-mtp gvfs-gphoto2 gvfs-afc
    usbmuxd libimobiledevice android-udev
    thunar-volman tumbler thunar-archive-plugin

    # Shell, Menus & Clipboard
    rofi-wayland cliphist wl-clipboard
    grim slurp swappy jq libnotify

    # Audio & Hardware
    pipewire pipewire-pulse wireplumber playerctl
    bluez bluez-utils networkmanager brightnessctl

    # C / Rust Build Toolchain & Libraries
    base-devel rust cargo gcc make pkg-config
    gtk4 cairo glib2 json-c

    # Fonts
    ttf-jetbrains-mono-nerd ttf-font-awesome noto-fonts-emoji
)

AUR_PACKAGES=(
    # Quickshell Wayland layer-shell engine
    quickshell
    # VSCodium
    vscodium-bin
)

log_info "Installing official repository packages..."
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

log_info "Installing AUR packages..."
"$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}"

# 4. Service Activation (Phone cable sharing, Bluetooth, Network)
log_info "Configuring system services and socket activation..."
sudo systemctl enable --now NetworkManager.service
sudo systemctl enable --now bluetooth.service

# Socket-activate usbmuxd (zero RAM when no iPhone is plugged in)
sudo systemctl enable usbmuxd.socket
sudo systemctl start usbmuxd.socket || true

log_ok "Services configured."

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

# Symlink or Copy Hyprland Lua modules
cp -rf "$ROOT_DIR/hypr/"* "$CONFIG_HOME/hypr/"
log_ok "Hyprland Lua modules deployed to $CONFIG_HOME/hypr/"

# Foot configuration
mkdir -p "$CONFIG_HOME/foot"
if [[ -f "$ROOT_DIR/foot/foot.ini" ]]; then
    cp -f "$ROOT_DIR/foot/foot.ini" "$CONFIG_HOME/foot/foot.ini"
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
printf "  • Launch with: %bHyprland%b\n" "$bold$blue" "$reset"
printf "  • App Launcher: %bSUPER + A%b (0ms instant pop-in)\n" "$bold$green" "$reset"
printf "  • Clipboard:    %bSUPER + C%b (Anchored top-right)\n" "$bold$green" "$reset"
printf "  • Wallpaper:    %bSUPER + W%b (Cinematic Wallpaper Shower)\n" "$bold$green" "$reset"
printf "  • Codium:       %bSUPER + O%b\n" "$bold$green" "$reset"
printf "  • Phone Sharing:%bPlug in Android (MTP) or iPhone (AFC) to Thunar%b\n\n" "$bold$yellow" "$reset"
