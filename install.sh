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
    qt6-5compat qt6-svg qt6-multimedia-ffmpeg qt6-imageformats

    # Audio, network, hardware
    pipewire pipewire-pulse wireplumber playerctl
    bluez bluez-utils networkmanager upower power-profiles-daemon
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
# Quickshell's PowerProfiles API needs the daemon; without it the island's
# Performance profile choice is greyed out and cycling does nothing.
sudo systemctl enable --now power-profiles-daemon.service 2>/dev/null     || log_warn "power-profiles-daemon could not be enabled (tuned may own the profile API)" 
# SDDM must be enabled on BIOS/MBR systems too, otherwise the machine boots
# straight to a black console with no greeter.
if systemctl list-unit-files sddm.service >/dev/null 2>&1; then
    sudo systemctl enable sddm.service
    sudo systemctl set-default graphical.target
fi

# -----------------------------------------------------------------------------
# 5. Native builds
# -----------------------------------------------------------------------------
log_info "Building native components..."
mkdir -p "$ROOT_DIR/build"

log_info "  • zenith-ctl (C toggle dispatcher)"
gcc -O3 -Wall -Wextra "$ROOT_DIR/native/zenith-ctl.c" -o "$ROOT_DIR/build/zenith-ctl"
chmod +x "$ROOT_DIR/build/zenith-ctl"

log_info "  • zenith-notifyctl (C notification bridge client)"
gcc -O3 -Wall -Wextra "$ROOT_DIR/native/zenith-notifyctl.c" -o "$ROOT_DIR/build/zenith-notifyctl"
chmod +x "$ROOT_DIR/build/zenith-notifyctl"

log_info "  • zenith-native (Rust wallpaper/theme/notification engine)"
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
sed -i "s|\$HOME|$HOME|g" "$CONFIG_HOME/hypr/hypridle.conf"
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

# Zenith Display font (lock screen + SDDM). Installed system-wide
# so both the user session and the SDDM greeter can resolve it.
if [[ -f "$ROOT_DIR/fonts/ZenithDisplay-Bold.ttf" ]]; then
    sudo mkdir -p /usr/share/fonts/zenith
    sudo cp -f "$ROOT_DIR/fonts/ZenithDisplay-Bold.ttf" /usr/share/fonts/zenith/
    sudo fc-cache -f /usr/share/fonts/zenith >/dev/null 2>&1 || fc-cache -f >/dev/null 2>&1 || true
fi


# SDDM greeter theme (login screen mirrors the lock screen)
if [[ -d "$ROOT_DIR/sddm/silent" ]]; then
    grep -q '^\[SddmGreeterTheme\]' "$ROOT_DIR/sddm/silent/metadata.desktop" \
        || die "SDDM theme metadata is missing the [SddmGreeterTheme] group"
    grep -q '^QtVersion=6' "$ROOT_DIR/sddm/silent/metadata.desktop" \
        || die "SDDM theme must declare QtVersion=6 on Arch"

    sudo mkdir -p /usr/share/sddm/themes /etc/sddm.conf.d /var/lib/zenith
    sudo rm -rf /usr/share/sddm/themes/zenith
    sudo cp -r "$ROOT_DIR/sddm/silent" /usr/share/sddm/themes/
    sudo chmod -R a+rX /usr/share/sddm/themes/zenith
    sudo tee /etc/sddm.conf.d/zenith-theme.conf >/dev/null <<'CONF'
[Theme]
Current=zenith
CONF

    # Greeter runs as the sddm user and cannot read $HOME. Seed everything it
    # needs before first login; the native engine keeps it in sync later.
    sddm_owner="${USER:-$(id -un)}"
    sudo chown "$sddm_owner:$sddm_owner" /var/lib/zenith
    chmod 755 /var/lib/zenith

    if [[ -f "$CACHE_HOME/zenith/wall.lock.png" ]]; then
        sudo cp -f "$CACHE_HOME/zenith/wall.lock.png" /var/lib/zenith/lock-bg.png
    else
        # Fresh install: derive a tinted background from a shipped wallpaper so
        # the greeter is never a black rectangle on first boot.
        fallback_wallpaper=$(find "$ROOT_DIR/wallpapers" -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null \
            | sort | head -n1 || true)
        if [[ -n "$fallback_wallpaper" ]] && command -v magick >/dev/null 2>&1; then
            sudo magick "$fallback_wallpaper" -auto-orient \
                -resize 1920x1080^ -gravity center -extent 1920x1080 \
                -blur 0x14 -fill '#0a0c12' -colorize 38% \
                /var/lib/zenith/lock-bg.png >/dev/null 2>&1 || true
        fi
    fi
    if [[ -f /var/lib/zenith/lock-bg.png ]]; then
        sudo chmod 644 /var/lib/zenith/lock-bg.png
    fi

    # Shared palette QML consumed by Main.qml's Loader.
    palette_source="$STATE_HOME/zenith/palette.json"
    [[ -f "$palette_source" ]] || palette_source="$ROOT_DIR/generated/palette.json"
    if [[ -f "$palette_source" ]] && command -v jq >/dev/null 2>&1; then
        palette_mode=$(jq -r '.mode // "dark"' "$palette_source")
        if [[ "$palette_mode" == "light" ]]; then palette_group="light"; else palette_group="dark"; fi
        sudo tee /var/lib/zenith/palette.qml >/dev/null <<QML
import QtQml

QtObject {
    readonly property color accent: "$(jq -r --arg g "$palette_group" '.[$g].primary // "#c7c3ff"' "$palette_source")"
    readonly property color surface: "$(jq -r --arg g "$palette_group" '.[$g].surfaceContainerHigh // "#2a2931"' "$palette_source")"
    readonly property color onSurface: "$(jq -r --arg g "$palette_group" '.[$g].onSurface // "#e6e1e9"' "$palette_source")"
    readonly property color onSurfaceVariant: "$(jq -r --arg g "$palette_group" '.[$g].onSurfaceVariant // "#c9c5cf"' "$palette_source")"
    readonly property color error: "$(jq -r --arg g "$palette_group" '.[$g].error // "#ffb4ab"' "$palette_source")"
    readonly property color outlineVariant: "$(jq -r --arg g "$palette_group" '.[$g].outlineVariant // "#48464f"' "$palette_source")"
}
QML
        sudo chown "$sddm_owner:$sddm_owner" /var/lib/zenith/palette.qml
        sudo chmod 644 /var/lib/zenith/palette.qml
    fi

    # Wallpaper avatar: a centre crop shared by hyprlock and the greeter.
    avatar_source=""
    if [[ -f "$CACHE_HOME/zenith/wall.lock.png" ]]; then
        avatar_source="$CACHE_HOME/zenith/wall.lock.png"
    else
        avatar_source=$(find "$ROOT_DIR/wallpapers" -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null \
            | sort | head -n1 || true)
    fi
    if [[ -n "$avatar_source" ]] && command -v magick >/dev/null 2>&1; then
        mkdir -p "$CACHE_HOME/zenith"
        avatar_tmp="$CACHE_HOME/zenith/avatar-install.png"
        if magick "$avatar_source" -auto-orient \
                -resize 256x256^ -gravity center -extent 256x256 \
                "$avatar_tmp" >/dev/null 2>&1; then
            mv -f "$avatar_tmp" "$CACHE_HOME/zenith/avatar.png"
            sudo cp -f "$CACHE_HOME/zenith/avatar.png" /var/lib/zenith/avatar.png
            sudo chmod 644 /var/lib/zenith/avatar.png
            # The greeter reads the user's face icon from ~/.face.icon
            cp -f "$CACHE_HOME/zenith/avatar.png" "$HOME/.face.icon"
            chmod 644 "$HOME/.face.icon" >/dev/null 2>&1 || true
        else
            rm -f "$avatar_tmp" 2>/dev/null || true
        fi
    fi
    sh "$ROOT_DIR/scripts/lock-status.sh" snapshot >/dev/null 2>&1 || true

    sudo fc-cache -f >/dev/null 2>&1 || true
    log_ok "SDDM greeter deployed (login screen matches the lock screen)."
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