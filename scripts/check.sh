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
log_fail() { printf "%b[FAIL]%b  %s\n" "$red" "$reset" "$*" >&2; exit 1; }

ZENITH_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

log_info "Running Zenith System Verification in: $ZENITH_ROOT"

# 1. Zero-Python Policy Check
log_info "Verifying strict Zero-Python Standard..."
py_count=$(find "$ZENITH_ROOT" -type f -name "*.py" | wc -l)
if [[ "$py_count" -gt 0 ]]; then
    log_fail "Found $py_count Python files in Zenith! Zero-Python standard violated."
fi
log_ok "Zero Python files detected across entire repository."

# 2. Key Directories Check
log_info "Verifying directory structure..."
for d in hypr native rofi island services components foot wallpapers scripts; do
    if [[ ! -d "$ZENITH_ROOT/$d" ]]; then
        log_fail "Missing core directory: $d"
    fi
done
log_ok "All core directories verified."

# 3. Modular Lua Syntax Validation
log_info "Validating Hyprland Lua modules..."
if command -v lua >/dev/null 2>&1; then
    for f in "$ZENITH_ROOT/hypr/"*.lua; do
        lua -p "$f" || log_fail "Syntax error in $f"
    done
    log_ok "All Hyprland Lua modules passed syntax check."
else
    log_info "Lua binary not installed on host; skipping syntax parse."
fi

# 4. Native Tooling Presence
log_info "Verifying native build sources..."
[[ -f "$ZENITH_ROOT/native/zenith-ctl.c" ]] || log_fail "Missing native/zenith-ctl.c"
[[ -f "$ZENITH_ROOT/native/gallery.c" ]]    || log_fail "Missing native/gallery.c"
[[ -f "$ZENITH_ROOT/native/Cargo.toml" ]]   || log_fail "Missing native/Cargo.toml"
log_ok "All native source targets are present."

# 5. Core Application Dependencies
log_info "Checking runtime commands..."
for cmd in hyprland foot rofi thunar firefox; do
    if command -v "$cmd" >/dev/null 2>&1; then
        log_ok "Found: $cmd"
    else
        printf "%b[WARN]%b  Command '%s' not yet installed in host environment (will be installed by ./install.sh)\n" "$yellow" "$reset" "$cmd"
    fi
done

printf "\n%bZenith verification PASSED successfully!%b\n" "$bold$green" "$reset"
