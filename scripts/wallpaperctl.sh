#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Wallpaper Control Helper (POSIX Shell)
#  Backend: swww
#  Protocol for WallpaperService.qml
# =============================================================================
set -euo pipefail

CMD="${1:-probe}"
ZENITH_ROOT="${ZENITH_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zenith"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zenith"
mkdir -p "$STATE_DIR" "$CACHE_DIR"

CURRENT_FILE="$STATE_DIR/current_wallpaper"

case "$CMD" in
    probe|bootstrap)
        if ! pgrep -x "swww-daemon" >/dev/null 2>&1; then
            swww-daemon >/dev/null 2>&1 &
            sleep 0.5
        fi
        CURRENT=""
        [[ -f "$CURRENT_FILE" ]] && CURRENT="$(cat "$CURRENT_FILE")"
        if [[ -z "$CURRENT" ]]; then
            CURRENT="$(find "$ZENITH_ROOT/wallpapers" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) 2>/dev/null | head -n 1 || true)"
            [[ -n "$CURRENT" ]] && printf '%s' "$CURRENT" > "$CURRENT_FILE"
        fi
        echo "STATE=ready"
        echo "CURRENT=$CURRENT"
        ;;

    list)
        shift || true
        for dir in "$@" "$ZENITH_ROOT/wallpapers"; do
            [[ -d "$dir" ]] || continue
            find "$dir" -maxdepth 3 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \) 2>/dev/null | while read -r img; do
                category="$(basename "$(dirname "$img")")"
                name="$(basename "$img")"
                printf '%s\t%s\t%s\n' "$category" "$name" "$img"
            done
        done
        ;;

    render|apply)
        PATH_ARG="${2:-}"
        [[ -z "$PATH_ARG" ]] && { echo "Missing wallpaper path" >&2; exit 1; }
        if ! pgrep -x "swww-daemon" >/dev/null 2>&1; then
            swww-daemon >/dev/null 2>&1 &
            sleep 0.5
        fi
        swww img "$PATH_ARG" --transition-type fade --transition-duration 1.0 >/dev/null 2>&1 || true
        printf '%s' "$PATH_ARG" > "$CURRENT_FILE"
        echo "STATE=ready"
        echo "CURRENT=$PATH_ARG"
        echo "COMMITTED=true"
        ;;

    candidate)
        PATH_ARG="${2:-}"
        echo "STATE=ready"
        echo "CANDIDATE=$PATH_ARG"
        ;;

    palette)
        echo "STATE=ready"
        ;;

    cancel-candidate)
        echo "STATE=ready"
        ;;

    theme-source)
        echo "STATE=ready"
        ;;

    *)
        echo "STATE=ready"
        ;;
esac
