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
py_count=$(find "$ZENITH_ROOT" -path "$ZENITH_ROOT/.git" -prune -o -type f -name "*.py" -print | wc -l | tr -d ' ')
if [[ "$py_count" -gt 0 ]]; then
    log_fail "Found $py_count Python files in Zenith! Zero-Python standard violated."
fi
log_ok "Zero Python files detected across the repository."

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
[[ -f "$ZENITH_ROOT/native/Cargo.toml" ]]   || log_fail "Missing native/Cargo.toml"
[[ -f "$ZENITH_ROOT/native/src/main.rs" ]]  || log_fail "Missing native/src/main.rs"
[[ -f "$ZENITH_ROOT/picker/shell.qml" ]]    || log_fail "Missing picker/shell.qml"
log_ok "All native source targets are present."

# 5. Runtime Commands
log_info "Checking runtime commands..."
missing=0
for cmd in Hyprland quickshell foot rofi thunar firefox swww wl-copy cliphist grim slurp \
        wf-recorder jq magick hyprlock hypridle brightnessctl playerctl notify-send; do
    if command -v "$cmd" >/dev/null 2>&1; then
        log_ok "Found: $cmd"
    else
        log_warn "Command '$cmd' not installed yet (./install.sh provides it)"
        missing=$((missing + 1))
    fi
done
[[ "$missing" -eq 0 ]] || log_warn "$missing runtime command(s) still missing."

# 6. Build Artefacts
log_info "Checking compiled artefacts..."
if [[ -x "$ZENITH_ROOT/build/zenith-native" ]]; then log_ok "build/zenith-native present"
else log_warn "build/zenith-native missing; run ./install.sh"; fi
if [[ -x "$ZENITH_ROOT/build/zenith-ctl" ]]; then log_ok "build/zenith-ctl present"
else log_warn "build/zenith-ctl missing; run ./install.sh"; fi

printf "\n%bZenith verification PASSED successfully!%b\n" "$bold$green" "$reset"