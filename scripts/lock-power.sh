#!/bin/sh
# lock-power.sh — Windows-style power popup state machine for Zenith lock screen
# State: hidden | open  stored at /run/user/$UID/zenith/lock-power-state

STATE_DIR="/run/user/${UID}/zenith"
STATE_FILE="${STATE_DIR}/lock-power-state"

_ensure_dir() { mkdir -p "$STATE_DIR"; }
_get_state() { cat "$STATE_FILE" 2>/dev/null || echo "hidden"; }
_set_state() { _ensure_dir; printf '%s' "$1" > "$STATE_FILE"; }

case "$1" in
  toggle)
    if [ "$(_get_state)" = "open" ]; then
      _set_state "hidden"
    else
      _set_state "open"
    fi
    ;;
  cancel)
    _set_state "hidden"
    ;;
  action)
    _set_state "hidden"
    case "$2" in
      suspend)  systemctl suspend ;;
      reboot)   systemctl reboot ;;
      shutdown) systemctl poweroff ;;
    esac
    ;;
  label)
    STATE="$(_get_state)"
    case "$2" in
      power)
        if [ "$STATE" = "open" ]; then printf '✕'; else printf '⏻'; fi
        ;;
      suspend)
        [ "$STATE" = "open" ] && printf '󰒲  Suspend' || printf ''
        ;;
      reboot)
        [ "$STATE" = "open" ] && printf '󰑓  Reboot' || printf ''
        ;;
      shutdown)
        [ "$STATE" = "open" ] && printf '󰐥  Shutdown' || printf ''
        ;;
      cancel)
        [ "$STATE" = "open" ] && printf '󰅙  Cancel' || printf ''
        ;;
    esac
    ;;
  *)
    echo "Usage: lock-power.sh toggle|cancel|action <suspend|reboot|shutdown>|label <power|suspend|reboot|shutdown|cancel>" >&2
    exit 1
    ;;
esac
