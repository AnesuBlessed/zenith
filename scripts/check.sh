#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Environment & Subsystem Verification Script
# =============================================================================
set -euo pipefail

bold="\033[1m"
green="\033[32m"
blue="\033[34m"
yellow="\033[33m"
red="\033[31m"
reset="\033[0m"

log_info() { printf "%b[INFO]%b  %s\n" "$blue" "$reset" "$*"; }
log_ok()   { printf "%b[PASS]%b  %s\n" "$green" "$reset" "$*"; }
log_warn() { printf "%b[WARN]%b  %s\n" "$yellow" "$reset" "$*"; }
log_fail() { printf "%b[FAIL]%b  %s\n" "$red" "$reset" "$*" >&2; exit 1; }

ZENITH_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

log_info "Running Zenith System Verification in: $ZENITH_ROOT"

# 1. Zero-Python Policy
log_info "Verifying strict Zero-Python standard..."
# tools/ is a developer-only area: the font derivative generator lives there
# and its generated TTF is committed, so runtime Zenith stays Python-free.
py_count=$(find "$ZENITH_ROOT" -path "$ZENITH_ROOT/.git" -prune -o \
    -path "$ZENITH_ROOT/tools" -prune -o -type f -name "*.py" -print \
    | wc -l | tr -d ' ')
if [[ "$py_count" -gt 0 ]]; then
    log_fail "Found $py_count Python files in Zenith! Zero-Python standard violated."
fi
log_ok "Zero Python files detected in runtime components."

# 2. Key Directories
log_info "Verifying directory structure..."
for d in hypr native rofi island services components foot wallpapers scripts picker; do
    [[ -d "$ZENITH_ROOT/$d" ]] || log_fail "Missing core directory: $d"
done
log_ok "All core directories verified."

# 3. Modular Lua Syntax
log_info "Validating Hyprland Lua modules..."
if command -v lua >/dev/null 2>&1; then
    for f in "$ZENITH_ROOT/hypr/"*.lua; do
        lua -e "assert(loadfile([[$f]]))" || log_fail "Syntax error in $f"
    done
    log_ok "All Hyprland Lua modules passed syntax check."
else
    log_info "Lua binary not installed on host; skipping syntax parse."
fi

# 4. Native Sources
log_info "Verifying native build sources..."
[[ -f "$ZENITH_ROOT/native/zenith-ctl.c" ]] || log_fail "Missing native/zenith-ctl.c"
[[ -f "$ZENITH_ROOT/native/zenith-notifyctl.c" ]] || log_fail "Missing native/zenith-notifyctl.c"
[[ -f "$ZENITH_ROOT/native/Cargo.toml" ]]   || log_fail "Missing native/Cargo.toml"
[[ -f "$ZENITH_ROOT/native/src/main.rs" ]]  || log_fail "Missing native/src/main.rs"
[[ -f "$ZENITH_ROOT/native/src/notify.rs" ]] || log_fail "Missing native/src/notify.rs"
[[ -f "$ZENITH_ROOT/picker/shell.qml" ]]    || log_fail "Missing picker/shell.qml"
log_ok "All native source targets are present."

# 5. Runtime Commands
log_info "Checking runtime commands..."
missing=0
for cmd in Hyprland quickshell foot rofi thunar firefox awww wl-copy cliphist grim slurp \
        wf-recorder jq magick hyprlock hypridle brightnessctl playerctl notify-send sddm; do
    if command -v "$cmd" >/dev/null 2>&1; then
        log_ok "Found: $cmd"
    else
        log_warn "Command '$cmd' not installed; install.sh auto-installs it on the next run"
        missing=$((missing + 1))
    fi
done
[[ "$missing" -eq 0 ]] || log_warn "$missing runtime command(s) still missing."

# 6. SDDM greeter theme
log_info "Validating SDDM greeter theme..."
sddm_theme="$ZENITH_ROOT/sddm/silent"
metadata="$sddm_theme/metadata.desktop"
[[ -f "$metadata" ]] || log_fail "Missing sddm/silent/metadata.desktop"
grep -q '^\[SddmGreeterTheme\]' "$metadata" \
    || log_fail "SDDM metadata must use the [SddmGreeterTheme] group"
grep -q '^MainScript=Main.qml' "$metadata" \
    || log_fail "SDDM metadata is missing MainScript=Main.qml"
grep -q '^QtVersion=6' "$metadata" \
    || log_fail "SDDM metadata must declare QtVersion=6"
[[ -f "$sddm_theme/Main.qml" ]] || log_fail "Missing sddm/silent/Main.qml"
grep -q 'Theme-Id=zenith' "$metadata" \
    || log_fail "SDDM metadata must declare Theme-Id=zenith"
[[ -f "$sddm_theme/components/Config.qml" ]] \
    || log_fail "Missing SilentSDDM engine (components/Config.qml)"
[[ -f "$sddm_theme/components/LoginScreen.qml" ]] \
    || log_fail "Missing SilentSDDM LoginScreen component"

# Our theme is wired through metadata.desktop -> configs/zenith.conf and
# uses Zenith Display everywhere the rei preset set RedHatDisplay.
grep -q '^ConfigFile=configs/zenith.conf' "$metadata" \
    || log_fail "SDDM metadata must point ConfigFile at configs/zenith.conf"
[[ -f "$sddm_theme/configs/zenith.conf" ]] \
    || log_fail "Missing sddm/silent/configs/zenith.conf"
grep -q 'font-family = "Zenith Display"' "$sddm_theme/configs/zenith.conf" \
    || log_fail "Zenith greeter config does not use Zenith Display"
[[ -f "$sddm_theme/backgrounds/rei.mp4" ]] \
    || log_fail "Missing SilentSDDM Rei background video"
[[ -f "$sddm_theme/backgrounds/rei.png" ]] \
    || log_fail "Missing Rei poster fallback"
grep -q 'import QtMultimedia' "$sddm_theme/Main.qml" \
    || log_fail "SDDM greeter has no QtMultimedia video support"
if grep -q 'lock-power' "$ZENITH_ROOT/hypr/hyprlock.conf"; then
    log_fail "hyprlock still contains the removed power popup"
fi
grep -q 'fade_on_empty = false' "$ZENITH_ROOT/hypr/hyprlock.conf" \
    || log_fail "hyprlock password field is not always visible"
log_ok "SDDM theme source is structurally valid."

if [[ -d /usr/share/sddm/themes/zenith ]]; then
    log_ok "SDDM theme installed at /usr/share/sddm/themes/zenith"
else
    log_warn "SDDM theme not installed yet; run ./install.sh"
fi
if [[ -f /etc/sddm.conf.d/zenith-theme.conf ]] \
        && grep -q '^Current=zenith' /etc/sddm.conf.d/zenith-theme.conf; then
    log_ok "SDDM is configured to use the Zenith theme"
else
    log_warn "Zenith is not the active SDDM theme; run ./install.sh"
fi
if command -v systemctl >/dev/null 2>&1 \
        && systemctl is-enabled sddm.service >/dev/null 2>&1; then
    log_ok "sddm.service is enabled"
else
    log_warn "sddm.service is not enabled; run ./install.sh"
fi
for artifact in lock-bg.png palette.qml avatar.png lock-status.qml; do
    if [[ -f "/var/lib/zenith/$artifact" ]]; then
        log_ok "SDDM shared asset present: $artifact"
    else
        log_warn "SDDM shared asset missing: /var/lib/zenith/$artifact"
    fi
done
if command -v fc-match >/dev/null 2>&1 \
        && fc-match "Zenith Display" | grep -qi "Zenith Display"; then
    log_ok "Zenith Display font resolves"
else
    log_warn "Zenith Display font is not installed or not resolvable"
fi

# 7. Build Artefacts
log_info "Checking compiled artefacts..."
if [[ -x "$ZENITH_ROOT/build/zenith-native" ]]; then log_ok "build/zenith-native present"
else log_warn "build/zenith-native missing; run ./install.sh"; fi
if [[ -x "$ZENITH_ROOT/build/zenith-ctl" ]]; then log_ok "build/zenith-ctl present"
else log_warn "build/zenith-ctl missing; run ./install.sh"; fi
if [[ -x "$ZENITH_ROOT/build/zenith-notifyctl" ]]; then log_ok "build/zenith-notifyctl present"
else log_warn "build/zenith-notifyctl missing; run ./install.sh"; fi

printf "\n%bZenith verification PASSED successfully!%b\n" "$bold$green" "$reset"