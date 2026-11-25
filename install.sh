#!/usr/bin/env bash
# =============================================================================
#  PROJECT ZENITH — Arch Linux Installer
# =============================================================================
#  Supports: Arch Linux, EndeavourOS, CachyOS, Manjaro, Garuda, ArcoLinux
#  Zero Python: compiled Rust + C, POSIX shell, Quickshell/QML.
# =============================================================================
set -euo pipefail

bold="\033[1m"; dim="\033[2m"; green="\033[32m"; blue="\033[34m"
yellow="\033[33m"; red="\033[31m"; reset="\033[0m"

log_info()  { printf "%b[INFO]%b  %s\n" "$blue" "$reset" "$*"; }
log_ok()    { printf "%b[OK]%b    %s\n" "$green" "$reset" "$*"; }
log_warn()  { printf "%b[WARN]%b  %s\n" "$yellow" "$reset" "$*"; }
log_err()   { printf "%b[ERROR]%b %s\n" "$red" "$reset" "$*" >&2; }
die()       { log_err "$*"; exit 1; }

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[[ "$EUID" -ne 0 ]] || die "Run the installer as your desktop user, not as root."

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

# -----------------------------------------------------------------------------
# 1. Host verification
# -----------------------------------------------------------------------------
[[ -r /etc/os-release ]] || die "/etc/os-release missing; cannot verify distribution."
# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "arch" && ! "${ID_LIKE:-}" =~ arch ]]; then
    die "Zenith requires Arch Linux or an Arch derivative (detected ID=${ID:-unknown})."
fi
log_ok "Host: ${NAME:-Arch Linux}"

# -----------------------------------------------------------------------------
# 2. AUR helper
# -----------------------------------------------------------------------------
AUR_HELPER=""
if command -v paru >/dev/null 2>&1; then AUR_HELPER="paru"
elif command -v yay >/dev/null 2>&1; then AUR_HELPER="yay"
fi

install_yay() {
    log_info "Bootstrapping yay..."
    sudo pacman -S --needed --noconfirm base-devel git
    local tmp
    tmp="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
    AUR_HELPER="yay"
}
[[ -n "$AUR_HELPER" ]] || install_yay
log_ok "AUR helper: $AUR_HELPER"

# -----------------------------------------------------------------------------
# 3. Packages
# -----------------------------------------------------------------------------
PACKAGES=(
    # Compositor and Wayland stack
    hyprland hyprlock hypridle hyprpolkitagent
    xorg-xwayland wayland-protocols
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk

    # Desktop essentials
    foot firefox thunar gvfs gvfs-mtp gvfs-gphoto2 thunar-volman tumbler
    thunar-archive-plugin android-udev

    # Shell, launcher, clipboard, capture
    rofi-wayland cliphist wl-clipboard grim slurp swappy wf-recorder
    # Wallpaper daemon (swww was renamed upstream to awww; identical CLI)
    awww jq imagemagick libnotify fastfetch ffmpeg
    qt6-5compat qt6-svg

    # Audio, network, hardware
    pipewire pipewire-pulse wireplumber playerctl
    bluez bluez-utils networkmanager upower
    brightnessctl pciutils wireless_tools curl polkit

    # Build toolchain
    base-devel rust cargo gcc make pkg-config lua git

    # Fonts
    ttf-jetbrains-mono-nerd ttf-font-awesome noto-fonts-emoji

    # Display manager and OCR
    sddm tesseract tesseract-data-eng
)

AUR_PACKAGES=(
    quickshell
)
AUR_OPTIONAL=(
    vscodium-bin
    tela-circle-icon-theme-dracula
)

log_info "Installing repository packages..."
sudo pacman -S --needed --noconfirm --ask 4 "${PACKAGES[@]}"

log_info "Installing AUR packages..."
"$AUR_HELPER" -S --needed --noconfirm "${AUR_PACKAGES[@]}"

log_info "Installing optional desktop extras..."
for pkg in "${AUR_OPTIONAL[@]}"; do
    "$AUR_HELPER" -S --needed --noconfirm --ask 4 "$pkg" \
        || log_warn "$pkg unavailable; its integration stays optional."
done

log_info "Installing optional video-wallpaper backend (mpvpaper)..."
# mpvpaper ships in the CachyOS repos — plain pacman honors --ask 4, so the
# libmpv provider prompt never blocks; the AUR helper re-asks interactively.
sudo pacman -S --needed --noconfirm --ask 4 mpvpaper 2>/dev/null \
    || log_warn "mpvpaper unavailable; animated video wallpapers stay disabled."

# -----------------------------------------------------------------------------
# 4. Services
# -----------------------------------------------------------------------------
log_info "Enabling system services..."
sudo systemctl enable --now NetworkManager.service
sudo systemctl enable --now bluetooth.service
if [[ -d /sys/firmware/efi ]]; then
    if systemctl list-unit-files sddm.service >/dev/null 2>&1; then
        sudo systemctl enable sddm.service
    fi
fi

# -----------------------------------------------------------------------------
# 5. Native builds
# -----------------------------------------------------------------------------
log_info "Building native components..."
mkdir -p "$ROOT_DIR/build"

log_info "  • zenith-ctl (C toggle dispatcher)"
gcc -O3 -Wall -Wextra "$ROOT_DIR/native/zenith-ctl.c" -o "$ROOT_DIR/build/zenith-ctl"
chmod +x "$ROOT_DIR/build/zenith-ctl"

log_info "  • zenith-native (Rust wallpaper/theme engine)"
(cd "$ROOT_DIR/native" && cargo build --release)
cp -f "$ROOT_DIR/native/target/release/zenith-native" "$ROOT_DIR/build/zenith-native"
chmod +x "$ROOT_DIR/build/zenith-native"
log_ok "Native components ready."

# -----------------------------------------------------------------------------
# 6. User configuration
# -----------------------------------------------------------------------------
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

mkdir -p "$CONFIG_HOME/hypr" "$CONFIG_HOME/foot" "$CONFIG_HOME/zenith" \
    "$CACHE_HOME/zenith" "$STATE_HOME/zenith" "$DATA_HOME/zenith"

printf '%s\n' "$ROOT_DIR" > "$CONFIG_HOME/zenith/root"

if [[ -f "$CONFIG_HOME/hypr/hyprland.lua" ]]; then
    backup="$CONFIG_HOME/hypr/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup"
    cp -f "$CONFIG_HOME/hypr/hyprland.lua" "$backup/" 2>/dev/null || true
    log_warn "Existing Hyprland config backed up to $backup (Zenith modules are deployed)."
fi
cp -rf "$ROOT_DIR/hypr/." "$CONFIG_HOME/hypr/"
# Hyprlock does not consistently expand $HOME inside path/cmd values.
sed -i "s|\$HOME|$HOME|g" "$CONFIG_HOME/hypr/hyprlock.conf"
if [[ ! -f "$CONFIG_HOME/zenith/settings.json" ]]; then
    bash "$ROOT_DIR/scripts/shortcutctl.sh" apply >/dev/null 2>&1 \
        || log_warn "Managed shortcuts were not generated; Super + W still opens the picker."
fi
log_ok "Hyprland Lua modules deployed."

# Scripts and assets are referenced by absolute path from Hyprland/QML.
rm -rf "$CONFIG_HOME/zenith/scripts" "$CONFIG_HOME/zenith/assets"
ln -s "$ROOT_DIR/scripts" "$CONFIG_HOME/zenith/scripts"
ln -s "$ROOT_DIR/assets" "$CONFIG_HOME/zenith/assets"
chmod +x "$ROOT_DIR/scripts/"*.sh

# Terminal, prompt and fastfetch
[[ -f "$ROOT_DIR/foot/foot.ini" ]] && cp -f "$ROOT_DIR/foot/foot.ini" "$CONFIG_HOME/foot/foot.ini"
# foot.ini includes colors.ini unconditionally; seed a neutral default so foot
# never starts with an include error. The wallpaper transaction overwrites it.
if [[ ! -f "$CONFIG_HOME/foot/colors.ini" ]]; then
    printf '[colors-dark]\nbackground=121217\nforeground=e6e1e9\n' \
        > "$CONFIG_HOME/foot/colors.ini"
fi
mkdir -p "$CONFIG_HOME/zenith/fastfetch"
cp -rf "$ROOT_DIR/fastfetch/." "$CONFIG_HOME/zenith/fastfetch/" 2>/dev/null || true
# fastfetch reads ~/.config/fastfetch; point it at the Zenith copy so the
# zen logo + config actually load. If the user already has a real fastfetch
# config directory, leave it alone and say so.
if [[ -L "$CONFIG_HOME/fastfetch" ]]; then
    ln -sfn "$CONFIG_HOME/zenith/fastfetch" "$CONFIG_HOME/fastfetch"
elif [[ -d "$CONFIG_HOME/fastfetch" ]]; then
    if [[ ! -f "$CONFIG_HOME/fastfetch/config.jsonc" ]]; then
        cp -rf "$ROOT_DIR/fastfetch/." "$CONFIG_HOME/fastfetch/" 2>/dev/null || true
    else
        log_warn "Found your own ~/.config/fastfetch config; Zenith's fastfetch theme was NOT applied."
    fi
else
    ln -sfn "$CONFIG_HOME/zenith/fastfetch" "$CONFIG_HOME/fastfetch"
fi

# Avatar placeholder for hyprlock
AVATAR="$CONFIG_HOME/zenith/assets/avatar.png"
if [[ ! -s "$AVATAR" ]]; then
    magick -size 200x200 xc:'#a899e6' -fill '#1b1226' -font DejaVu-Sans-Bold \
        -pointsize 96 -gravity center -annotate 0 'Z' "$AVATAR" 2>/dev/null \
        || magick -size 200x200 xc:'#a899e6' "$AVATAR"
fi

# -----------------------------------------------------------------------------
# 7. Defaults: palette, settings, theme consumers
# -----------------------------------------------------------------------------
if [[ -f "$ROOT_DIR/generated/palette.json" ]]; then
    cp -f "$ROOT_DIR/generated/palette.json" "$STATE_HOME/zenith/palette.json"
fi
# Consumers (rofi/hyprland/foot) are refreshed natively on first launch.

if [[ ! -f "$CONFIG_HOME/zenith/settings.json" ]]; then
    cat > "$CONFIG_HOME/zenith/settings.json" <<'JSON'
{
  "appearance": {
    "mode": "dark",
    "material": "solid",
    "surfaceOpacity": 0.96,
    "islandStyle": "floating",
    "wallpaperPaletteEnabled": true,
    "themeSourceMode": "wallpaper"
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
  },
  "shortcuts": {
    "managed": true
  }
}
JSON
fi

touch "$CACHE_HOME/zenith/theme-override.rasi"

if [[ -n "${WAYLAND_DISPLAY:-}" && -x "$ROOT_DIR/build/zenith-native" ]]; then
    log_info "Applying the initial wallpaper and palette..."
    if ! "$ROOT_DIR/build/zenith-native" wallpaper ensure >/dev/null; then
        log_warn "Wallpaper bootstrap failed — run 'build/zenith-native wallpaper ensure' to see why."
    fi
fi

# -----------------------------------------------------------------------------
# 7b. Auto-repair: verify every core command resolves; anything missing gets a
# targeted second pass (with the password prompt) instead of a warning.
# -----------------------------------------------------------------------------
log_info "Verifying core commands..."
CORE_PAIRS=(
    "hyprland:hyprland" "hyprlock:hyprlock" "hypridle:hypridle" "foot:foot"
    "rofi:rofi-wayland" "wl-copy:wl-clipboard" "cliphist:cliphist"
    "grim:grim" "slurp:slurp" "jq:jq" "magick:imagemagick"
    "hyprctl:hyprland" "awww:awww" "fastfetch:fastfetch" "ffmpeg:ffmpeg"
    "notify-send:libnotify" "brightnessctl:brightnessctl" "playerctl:playerctl"
    "wf-recorder:wf-recorder" "quickshell:quickshell"
)
missing=()
for pair in "${CORE_PAIRS[@]}"; do
    cmd="${pair%%:*}"
    command -v "$cmd" >/dev/null 2>&1 || missing+=("${pair#*:}")
done
if ((${#missing[@]} > 0)); then
    log_warn "Missing commands detected: ${missing[*]} — installing automatically..."
    sudo pacman -S --needed --noconfirm --ask 4 "${missing[@]}" \
        || log_warn "Repair pass failed; run './install.sh' again or install manually."
fi
log_ok "Core commands verified."

# Bluetooth radios shipped soft-blocked leave the shell reporting "Radio
# blocked"; lift it once at install time (the polkit path in the shell
# handles later blocks at runtime).
if command -v rfkill >/dev/null 2>&1; then
    rfkill unblock bluetooth 2>/dev/null || sudo rfkill unblock bluetooth 2>/dev/null \
        || true
fi

# -----------------------------------------------------------------------------
# 8. Shell prompt
# -----------------------------------------------------------------------------
if [[ -f "$HOME/.bashrc" ]] && ! grep -q "zenith/scripts/prompt.sh" "$HOME/.bashrc"; then
    printf '\n# Project Zenith prompt\n[ -f "%s/scripts/prompt.sh" ] && source "%s/scripts/prompt.sh"\n' \
        "$ROOT_DIR" "$ROOT_DIR" >> "$HOME/.bashrc"
fi

# -----------------------------------------------------------------------------
# 9. Verification
# -----------------------------------------------------------------------------
log_info "Verifying installation..."
bash "$ROOT_DIR/scripts/check.sh" || log_warn "Verification reported missing runtime tools."

printf "\n%b" "$bold$green"
cat << "EOF"
  ======================================================
     PROJECT ZENITH INSTALLATION COMPLETE
  ======================================================
EOF
printf "%b\n" "$reset"
printf "  • Start:      %bHyprland%b (or log out and pick Hyprland in SDDM)\n" "$bold$blue" "$reset"
printf "  • Launcher:   %bSUPER + A%b\n" "$bold$green" "$reset"
printf "  • Clipboard:  %bSUPER + V%b\n" "$bold$green" "$reset"
printf "  • Wallpapers: %bSUPER + W%b (standalone picker)\n" "$bold$green" "$reset"
printf "  • Settings:   %bSUPER + ,%b\n\n" "$bold$green" "$reset"

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    log_info "Run 'Hyprland' (or log in through SDDM) to start Zenith."
fi