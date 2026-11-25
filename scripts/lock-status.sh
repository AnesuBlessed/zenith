#!/bin/sh
# lock-status.sh — Dynamic widget data for Zenith lock screen

case "$1" in
  battery)
    # Try upower first, fall back to sysfs
    LEVEL=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || \
            cat /sys/class/power_supply/BAT1/capacity 2>/dev/null)
    STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || \
             cat /sys/class/power_supply/BAT1/status 2>/dev/null)
    [ -z "$LEVEL" ] && exit 0
    if [ "$STATUS" = "Charging" ]; then
      ICON='󰂄'
    elif [ "$LEVEL" -ge 90 ]; then ICON='󰁹'
    elif [ "$LEVEL" -ge 70 ]; then ICON='󰂀'
    elif [ "$LEVEL" -ge 50 ]; then ICON='󰁾'
    elif [ "$LEVEL" -ge 30 ]; then ICON='󰁼'
    elif [ "$LEVEL" -ge 15 ]; then ICON='󰁺'
    else ICON='󰂃'
    fi
    printf '%s %s%%' "$ICON" "$LEVEL"
    ;;
  wifi)
    # NetworkManager first (iwgetid needs wireless-tools which many systems lack)
    SSID=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
    [ -z "$SSID" ] && SSID=$(iwgetid -r 2>/dev/null)
    if [ -n "$SSID" ]; then
      STRENGTH=$(nmcli -t -f IN-USE,SIGNAL dev wifi 2>/dev/null | awk -F: '$2!=""{if($2>max)max=$2}END{print max}')
      [ -z "$STRENGTH" ] && STRENGTH=$(awk 'NR==3{print int($3*100/70)}' /proc/net/wireless 2>/dev/null)
      if [ "${STRENGTH:-0}" -ge 75 ]; then ICON='󰤨'
      elif [ "${STRENGTH:-0}" -ge 50 ]; then ICON='󰤥'
      elif [ "${STRENGTH:-0}" -ge 25 ]; then ICON='󰤢'
      else ICON='󰤟'
      fi
      printf '%s  %s' "$ICON" "$SSID"
    else
      printf '󰤭  No WiFi'
    fi
    ;;
  weather)
    CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zenith/weather"
    if [ -f "$CACHE" ] && [ "$(find "$CACHE" -mmin -60 2>/dev/null)" ]; then
      cat "$CACHE"
    else
      # Fetch from wttr.in (brief format: icon + temp + condition)
      DATA=$(curl -sf --max-time 4 "wttr.in/?format=%c+%t+%C" 2>/dev/null)
      if [ -n "$DATA" ]; then
        mkdir -p "$(dirname "$CACHE")"
        printf '%s' "$DATA" > "$CACHE"
        printf '%s' "$DATA"
      fi
    fi
    ;;
  media)
    # Requires playerctl
    command -v playerctl >/dev/null 2>&1 || exit 0
    STATUS=$(playerctl status 2>/dev/null)
    [ "$STATUS" = "Playing" ] || [ "$STATUS" = "Paused" ] || exit 0
    ARTIST=$(playerctl metadata artist 2>/dev/null | cut -c1-24)
    TITLE=$(playerctl metadata title 2>/dev/null | cut -c1-28)
    [ -z "$ARTIST" ] && [ -z "$TITLE" ] && exit 0
    if [ "$STATUS" = "Playing" ]; then ICON='󰎆'; else ICON='󰏤'; fi
    printf '%s  %s — %s' "$ICON" "$ARTIST" "$TITLE"
    ;;
  *)
    echo "Usage: lock-status.sh battery|wifi|weather|media" >&2
    exit 1
    ;;
esac
