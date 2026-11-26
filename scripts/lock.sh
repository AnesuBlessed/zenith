#!/bin/sh
# lock.sh — Safe Zenith lock screen launcher
pgrep -x hyprlock >/dev/null 2>&1 && exit 0

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Refresh the status snapshot the SDDM greeter also reads, so both screens
# show the same weather/network/battery/media state.
"$SCRIPT_DIR/lock-status.sh" snapshot >/dev/null 2>&1 || true

# Drip behaviour: freeze the notification stack while the screen is locked
# (timers stop, nothing expires) and replay whatever is queued on unlock.
NOTIFYCTL="$SCRIPT_DIR/../build/zenith-notifyctl"
[ -x "$NOTIFYCTL" ] && "$NOTIFYCTL" hold >/dev/null 2>&1 &

# Not exec: the shell must survive so it can release the stack on unlock.
hyprlock

# Re-arm the stack: cards queued while locked replay now.
if [ -x "$NOTIFYCTL" ]; then
    "$NOTIFYCTL" release >/dev/null 2>&1
fi
