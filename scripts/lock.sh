#!/bin/sh
# lock.sh — Safe Zenith lock screen launcher
pgrep -x hyprlock >/dev/null 2>&1 && exit 0
# Reset power popup state
STATE_DIR="/run/user/${UID}/zenith"
printf 'hidden' > "${STATE_DIR}/lock-power-state" 2>/dev/null || true
exec hyprlock
