#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Session Control Helper (POSIX Shell)
# =============================================================================
set -euo pipefail

cmd="${1:-}"

case "$cmd" in
    lock)
        pidof hyprlock >/dev/null || hyprlock &
        ;;
    logout)
        hyprctl dispatch exit 0
        ;;
    suspend)
        systemctl suspend
        ;;
    reboot)
        systemctl reboot
        ;;
    poweroff|shutdown)
        systemctl poweroff
        ;;
    *)
        echo "Usage: sessionctl.sh {lock|logout|suspend|reboot|poweroff}" >&2
        exit 1
        ;;
esac
