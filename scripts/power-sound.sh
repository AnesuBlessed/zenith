#!/usr/bin/env bash
# =============================================================================
#  ZENITH — AC/Battery chime (optional, silent when no sound theme is present)
# =============================================================================
set -euo pipefail

case "${1:-}" in
    connected)    name="power-plug" ;;
    disconnected) name="power-unplug" ;;
    *) exit 0 ;;
esac

for dir in /usr/share/sounds/freedesktop/stereo /usr/share/sounds/gnome/default/alerts; do
    for ext in oga ogg wav; do
        file="$dir/$name.$ext"
        if [[ -f "$file" ]]; then
            if command -v paplay >/dev/null 2>&1; then paplay "$file" >/dev/null 2>&1 && exit 0; fi
            if command -v pw-play >/dev/null 2>&1; then pw-play "$file" >/dev/null 2>&1 && exit 0; fi
            if command -v aplay >/dev/null 2>&1; then aplay -q "$file" >/dev/null 2>&1 && exit 0; fi
        fi
    done
done
exit 0
