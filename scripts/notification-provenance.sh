#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Notification Provenance Observer (Zero-Python POSIX Shell)
#  Replaces notification-provenance.py.
#
#  Protocol (stdin → stdout):
#    IN:  <notificationId> <pid>
#    OUT: JSON {"notificationId":<id>,"pid":<pid>,"appId":"<exe-basename>"}
#
#  NotificationService.qml starts this process and feeds it PID lookups.
#  It reads lines from stdin and responds on stdout.
# =============================================================================

while IFS= read -r line; do
    notif_id="${line%% *}"
    pid="${line##* }"
    [[ -z "$notif_id" || -z "$pid" ]] && continue

    app_id=""
    # Try /proc/<pid>/exe first (most reliable)
    if [[ -r "/proc/$pid/exe" ]]; then
        exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
        [[ -n "$exe" ]] && app_id="$(basename "$exe")"
    fi

    # Fallback: /proc/<pid>/comm
    if [[ -z "$app_id" && -r "/proc/$pid/comm" ]]; then
        app_id="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
    fi

    printf '{"notificationId":%s,"pid":%s,"appId":"%s"}\n' \
        "$notif_id" "$pid" "${app_id:-unknown}"
done
