#!/usr/bin/env bash
# =============================================================================
#  ZENITH — External Theme Integration (hyprlock palette ownership)
# =============================================================================
#  Protocol (consumed by services/AppearanceService.qml):
#    manage-theme-integration.sh hyprlock enable|disable|refresh
# =============================================================================
set -euo pipefail

target="${1:-}"
action="${2:-}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
HYPRLOCK="$CONFIG_HOME/hypr/hyprlock.conf"
BACKUP="$STATE_HOME/zenith/hyprlock.backup"
PALETTE="$STATE_HOME/zenith/palette.json"
BEGIN="# >>> ZENITH PALETTE"
END="# <<< ZENITH PALETTE"
MARKER="$STATE_HOME/zenith/hyprlock-managed"

[[ "$target" == "hyprlock" ]] || { echo "manage-theme-integration: unsupported target '$target'" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "manage-theme-integration: jq is required" >&2; exit 1; }

palette_block() {
    local mode group
    mode="$(jq -r '.mode // "dark"' "$PALETTE")"
    [[ "$mode" == "light" ]] || mode="dark"
    group="$(jq -c --arg m "$mode" '.[$m] // .dark // {}' "$PALETTE")"
    token() { printf '%s' "$group" | jq -r --arg k "$1" '.[$k] // "#a899e6"'; }
    rgb() {
        local hex="${1#\#}"
        if [[ ${#hex} -ne 6 ]]; then printf 'rgb(168, 153, 230)'; return; fi
        printf 'rgb(%d, %d, %d)' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
    }
    local accent surface text muted warning
    accent="$(token primary)"
    surface="$(token surface)"
    text="$(token onSurface)"
    muted="$(token onSurfaceVariant)"
    warning="$(token error)"
    printf '%s\n' "$BEGIN"
    printf '\$accent   = %s\n' "$(rgb "$accent")"
    printf '\$base     = %s\n' "$(rgb "$surface")"
    printf '\$surface  = %s\n' "$(rgb "$(token surfaceContainer)")"
    printf '\$border   = %s\n' "$(rgb "$(token outlineVariant)")"
    printf '\$text     = %s\n' "$(rgb "$text")"
    printf '\$muted    = %s\n' "$(rgb "$muted")"
    printf '\$critical = %s\n' "$(rgb "$warning")"
    printf '\$popup    = %s\n' "$(rgb "$(token surfaceContainerHigh)")"
    printf '%s\n' "$END"
}

replace_block() {
    local source="$1"
    awk -v begin="$BEGIN" -v end="$END" -v blockfile="$source" '
        BEGIN { inside = 0 }
        index($0, begin) { while ((getline line < blockfile) > 0) print line; inside = 1; next }
        index($0, end) { inside = 0; next }
        inside { next }
        { print }
    ' "$HYPRLOCK" > "$HYPRLOCK.tmp" && mv "$HYPRLOCK.tmp" "$HYPRLOCK"
}

case "$action" in
    enable)
        [[ -f "$HYPRLOCK" ]] || { echo "manage-theme-integration: hyprlock.conf not found" >&2; exit 1; }
        [[ -f "$PALETTE" ]] || { echo "manage-theme-integration: palette.json not found" >&2; exit 1; }
        mkdir -p "$STATE_HOME/zenith"
        if [[ ! -f "$BACKUP" ]]; then cp -f "$HYPRLOCK" "$BACKUP"; fi
        palette_block > "$STATE_HOME/zenith/hyprlock-palette.conf"
        replace_block "$STATE_HOME/zenith/hyprlock-palette.conf"
        : > "$MARKER"
        echo "MANAGED=true"
        ;;

    refresh)
        if [[ -f "$MARKER" && -f "$PALETTE" && -f "$HYPRLOCK" ]]; then
            palette_block > "$STATE_HOME/zenith/hyprlock-palette.conf"
            replace_block "$STATE_HOME/zenith/hyprlock-palette.conf"
        fi
        echo "MANAGED=true"
        ;;

    disable)
        if [[ -f "$BACKUP" ]]; then
            cp -f "$BACKUP" "$HYPRLOCK"
            rm -f "$BACKUP"
        fi
        rm -f "$MARKER" "$STATE_HOME/zenith/hyprlock-palette.conf"
        echo "MANAGED=false"
        ;;

    *)
        echo "Usage: manage-theme-integration.sh hyprlock {enable|disable|refresh}" >&2
        exit 1
        ;;
esac