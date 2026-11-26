#!/bin/sh
# lock-status.sh — Dynamic widget data for Zenith lock screen
#
# The individual commands feed hyprlock's cmd[update:] labels. `snapshot`
# writes the same strings into a small QML object that the SDDM greeter loads,
# so the login screen and the lock screen show the same status widgets.
# Output is plain text so every label can use Zenith Display.

SNAPSHOT_FILE="/var/lib/zenith/lock-status.qml"

qml_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

case "$1" in
  battery)
    # Try upower first, fall back to sysfs
    LEVEL=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || \
            cat /sys/class/power_supply/BAT1/capacity 2>/dev/null)
    STATUS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || \
             cat /sys/class/power_supply/BAT1/status 2>/dev/null)
    [ -z "$LEVEL" ] && exit 0
    if [ "$STATUS" = "Charging" ]; then
      printf '%s%% charging' "$LEVEL"
    else
      printf '%s%%' "$LEVEL"
    fi
    ;;
  wifi)
    # NetworkManager first (iwgetid needs wireless-tools that many systems lack)
    SSID=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
    [ -z "$SSID" ] && SSID=$(iwgetid -r 2>/dev/null)
    if [ -n "$SSID" ]; then
      STRENGTH=$(nmcli -t -f IN-SSID,SIGNAL dev wifi 2>/dev/null | awk -F: '{if($2>max)max=$2}END{print max}')
      [ -z "$STRENGTH" ] && STRENGTH=$(awk 'NR==3{print int($3*100/70)}' /proc/net/wireless 2>/dev/null)
      if [ "${STRENGTH:-0}" -ge 75 ]; then QUALITY=excellent
      elif [ "${STRENGTH:-0}" -ge 50 ]; then QUALITY=good
      elif [ "${STRENGTH:-0}" -ge 25 ]; then QUALITY=okay
      else QUALITY=weak
      fi
      printf 'WiFi %s (%s)' "$SSID" "$QUALITY"
    else
      printf 'No WiFi'
    fi
    ;;
  weather)
    CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zenith/weather"
    if [ -f "$CACHE" ] && [ "$(find "$CACHE" -mmin -60 2>/dev/null)" ]; then
      cat "$CACHE"
    else
      # Fetch from wttr.in (temp + condition, no icon glyph)
      DATA=$(curl -sf --max-time 4 "wttr.in/?format=%t+%C" 2>/dev/null)
      if [ -n "$DATA" ]; then
        mkdir -p "$(dirname "$CACHE")"
        printf '%s' "$DATA" > "$CACHE"
        printf '%s' "$DATA"
      fi
    fi
    ;;
  temp)
    printf '%s' "$("$0" weather | awk '{print $1}' | sed 's/^+//')"
    ;;
  condition)
    printf '%s' "$("$0" weather | cut -d' ' -f2-)"
    ;;
  hilo)
    # H/L/feels from the Zenith weather cache (Open-Meteo via WeatherService)
    STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
    CACHE="$STATE/zenith/weather.json"
    [ -f "$CACHE" ] || exit 0
    jq -r '"H " + (.highTemperature|round|tostring) + "°C  L "
        + (.lowTemperature|round|tostring) + "°C · feels "
        + (.apparentTemperature|round|tostring) + "°C"' "$CACHE" 2>/dev/null
    ;;
  wicon)
    # Nerd-font weather glyph stored in the Zenith weather cache
    STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
    CACHE="$STATE/zenith/weather.json"
    if [ -f "$CACHE" ]; then
      jq -r '.icon' "$CACHE" 2>/dev/null
    else
      printf '󰖙'
    fi
    ;;
  ssid)
    SSID=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
    [ -z "$SSID" ] && SSID=$(iwgetid -r 2>/dev/null)
    if [ -n "$SSID" ]; then
      printf '%.14s' "$SSID"
    else
      printf 'offline'
    fi
    ;;
  bt)
    if command -v bluetoothctl >/dev/null 2>&1         && bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
      printf 'Bluetooth on'
    else
      printf 'Bluetooth off'
    fi
    ;;
  greeting)
    HOUR=$(date +%H)
    if [ "$HOUR" -ge 5 ] && [ "$HOUR" -lt 12 ]; then
      PART=morning; ICON='󰖙'
    elif [ "$HOUR" -ge 12 ] && [ "$HOUR" -lt 17 ]; then
      PART=afternoon; ICON='󰖙'
    elif [ "$HOUR" -ge 17 ] && [ "$HOUR" -lt 22 ]; then
      PART=evening; ICON='󰖜'
    else
      PART=night; ICON='󰖔'
    fi
    printf '%s Good %s, %s' "$ICON" "$PART" "$USER"
    ;;
  media)
    # Requires playerctl
    command -v playerctl >/dev/null 2>&1 || exit 0
    STATUS=$(playerctl status 2>/dev/null)
    [ "$STATUS" = "Playing" ] || [ "$STATUS" = "Paused" ] || exit 0
    ARTIST=$(playerctl metadata artist 2>/dev/null | cut -c1-24)
    TITLE=$(playerctl metadata title 2>/dev/null | cut -c1-28)
    [ -z "$ARTIST" ] || [ -z "$TITLE" ] && exit 0
    printf '%s — %s' "$ARTIST" "$TITLE"
    ;;
  snapshot)
    # Best-effort mirror for the SDDM greeter. The directory is created and
    # owned by install.sh; failure here must never prevent locking.
    [ -d "$(dirname "$SNAPSHOT_FILE")" ] || exit 0
    WEATHER=$("$0" weather 2>/dev/null)
    WIFI=$("$0" wifi 2>/dev/null)
    BATTERY=$("$0" battery 2>/dev/null)
    MEDIA=$("$0" media 2>/dev/null)
    TMP="${SNAPSHOT_FILE}.tmp.$$"
    {
      printf 'import QtQml\n\n'
      printf 'QtObject {\n'
      printf '  readonly property string weather: "%s"\n' "$(qml_escape "$WEATHER")"
      printf '  readonly property string wifi: "%s"\n' "$(qml_escape "$WIFI")"
      printf '  readonly property string battery: "%s"\n' "$(qml_escape "$BATTERY")"
      printf '  readonly property string media: "%s"\n' "$(qml_escape "$MEDIA")"
      printf '}\n'
    } > "$TMP" 2>/dev/null && mv -f "$TMP" "$SNAPSHOT_FILE" 2>/dev/null || {
      rm -f "$TMP" 2>/dev/null || true
      exit 0
    }
    ;;
  *)
    echo "Usage: lock-status.sh battery|wifi|weather|media|snapshot" >&2
    exit 1
    ;;
esac
