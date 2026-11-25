#!/bin/sh
# lock.sh — Safe Zenith lock screen launcher
pgrep -x hyprlock >/dev/null 2>&1 && exit 0

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Refresh the status snapshot the SDDM greeter also reads, so both screens
# show the same weather/network/battery/media state.
"$SCRIPT_DIR/lock-status.sh" snapshot >/dev/null 2>&1 || true
exec hyprlock
