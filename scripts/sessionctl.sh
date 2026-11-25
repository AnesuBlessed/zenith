#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Session Control Helper
# =============================================================================
#  Protocol (consumed by services/SessionService.qml):
#    probe   -> LOCK/LOGOUT/SUSPEND/HIBERNATE/REBOOT/SHUTDOWN=ready|missing
#    lock | logout | suspend | hibernate | reboot | shutdown
# =============================================================================
set -euo pipefail

cmd="${1:-}"
have() { command -v "$1" >/dev/null 2>&1; }

play_sound() {
    local helper="${ZENITH_ROOT:-$HOME/.config/zenith}/scripts/power-sound.sh"
    if [[ -x "$helper" ]]; then "$helper" "$1" >/dev/null 2>&1 || true; fi
}

case "$cmd" in
    probe)
        if have hyprlock || have loginctl; then echo "LOCK=ready"; else echo "LOCK=missing"; fi
        if have hyprctl; then echo "LOGOUT=ready"; else echo "LOGOUT=missing"; fi
        if have systemctl && systemctl can-suspend >/dev/null 2>&1; then echo "SUSPEND=ready"; else echo "SUSPEND=missing"; fi
        if have systemctl && systemctl can-hibernate >/dev/null 2>&1; then echo "HIBERNATE=ready"; else echo "HIBERNATE=missing"; fi
        if have systemctl; then echo "REBOOT=ready"; echo "SHUTDOWN=ready"; else echo "REBOOT=missing"; echo "SHUTDOWN=missing"; fi
        ;;

    lock)
        lock_helper="${ZENITH_ROOT:-$HOME/.config/zenith}/scripts/lock.sh"
        if [[ -x "$lock_helper" ]]; then exec "$lock_helper"; fi
        if have hyprlock; then exec hyprlock; fi
        loginctl lock-session
        ;;

    logout)
        hyprctl dispatch exit
        ;;

    suspend)
        play_sound disconnected
        systemctl suspend
        ;;

    hibernate)
        play_sound disconnected
        systemctl hibernate
        ;;

    reboot)
        play_sound disconnected
        systemctl reboot
        ;;

    shutdown)
        play_sound disconnected
        systemctl poweroff
        ;;

    *)
        echo "Usage: sessionctl.sh {probe|lock|logout|suspend|hibernate|reboot|shutdown}" >&2
        exit 1
        ;;
esac
