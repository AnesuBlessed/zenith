#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Terminal Theme Integration
# =============================================================================
#  Protocol (consumed by services/AppearanceService.qml):
#    terminal-integrations.sh status            -> TERMINAL_THEMING=enabled|disabled
#    terminal-integrations.sh enable|disable
#  Foot is always themed through ~/.config/foot/colors.ini (written by
#  zenith-native). Kitty is themed through a managed include when present.
# =============================================================================
set -euo pipefail

cmd="${1:-}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
PALETTE="$STATE_HOME/zenith/palette.json"
KITTY_DIR="$CONFIG_HOME/kitty"
KITTY_CONF="$KITTY_DIR/kitty.conf"
KITTY_THEME="$KITTY_DIR/zenith-theme.conf"
MARKER="# ZENITH-MANAGED-TERMINAL"
MARKER_FILE="$STATE_HOME/zenith/terminal-managed"

require_palette() {
    [[ -f "$PALETTE" ]] || { echo "terminal-integrations: palette.json not found" >&2; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "terminal-integrations: jq is required" >&2; exit 1; }
    mode="$(jq -r '.mode // "dark"' "$PALETTE")"
    [[ "$mode" == "light" ]] || mode="dark"
    group="$(jq -c --arg m "$mode" '.[$m] // .dark // {}' "$PALETTE")"
}

token() { printf '%s' "$group" | jq -r --arg k "$1" '.[$k] // "#a899e6"'; }

write_kitty() {
    local accent surface text muted container
    accent="$(token primary)"
    surface="$(token surface)"
    text="$(token onSurface)"
    muted="$(token onSurfaceVariant)"
    container="$(token surfaceContainer)"
    mkdir -p "$KITTY_DIR"
    cat > "$KITTY_THEME" <<EOF
# Zenith generated terminal palette — do not edit.
background      $surface
foreground      $text
cursor          $accent
selection_background $container
selection_foreground $text
url_color       $accent
active_border_color $accent
inactive_border_color $muted
color0  $surface
color1  $(token error)
color2  $(token success)
color3  $(token warning)
color4  $accent
color5  $(token tertiary)
color6  $(token secondary)
color7  $text
color8  $container
color9  $(token error)
color10 $(token success)
color11 $(token warning)
color12 $accent
color13 $(token tertiary)
color14 $(token secondary)
color15 $text
EOF
}

kitty_include_present() { [[ -f "$KITTY_CONF" ]] && grep -qF "$MARKER" "$KITTY_CONF"; }

case "$cmd" in
    status)
        if [[ -f "$MARKER_FILE" ]]; then
            echo "TERMINAL_THEMING=enabled"
        else
            echo "TERMINAL_THEMING=disabled"
        fi
        ;;

    enable)
        require_palette
        mkdir -p "$STATE_HOME/zenith"
        if [[ -d "$KITTY_DIR" ]]; then
            write_kitty
            if [[ -f "$KITTY_CONF" ]] && ! kitty_include_present; then
                printf '\n%s\ninclude %s\n' "$MARKER" "$KITTY_THEME" >> "$KITTY_CONF"
            elif [[ ! -f "$KITTY_CONF" ]]; then
                printf '%s\ninclude %s\n' "$MARKER" "$KITTY_THEME" > "$KITTY_CONF"
            fi
        fi
        : > "$MARKER_FILE"
        echo "TERMINAL_THEMING=enabled"
        ;;

    disable)
        if [[ -f "$KITTY_CONF" ]] && kitty_include_present; then
            awk -v marker="$MARKER" '
                index($0, marker) { skip = 1; next }
                skip { skip = 0; next }
                { print }
            ' "$KITTY_CONF" > "$KITTY_CONF.tmp" && mv "$KITTY_CONF.tmp" "$KITTY_CONF"
        fi
        rm -f "$KITTY_THEME" "$MARKER_FILE"
        echo "TERMINAL_THEMING=disabled"
        ;;

    *)
        echo "Usage: terminal-integrations.sh {status|enable|disable}" >&2
        exit 1
        ;;
esac
