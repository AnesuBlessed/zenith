#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Idle & Screen Inhibit Helper (POSIX Shell)
# =============================================================================
set -euo pipefail

cmd="${1:-}"

case "$cmd" in
    inhibit)
        # Prevent idle sleep via systemd-inhibit
        systemd-inhibit --what=idle:sleep --who=Zenith --why="User requested Keep-Awake" sleep infinity &
        echo $! > "${XDG_RUNTIME_DIR:-/tmp}/zenith-inhibit.pid"
        ;;
    uninhibit)
        pid_file="${XDG_RUNTIME_DIR:-/tmp}/zenith-inhibit.pid"
        if [[ -f "$pid_file" ]]; then
            kill "$(cat "$pid_file")" 2>/dev/null || true
            rm -f "$pid_file"
        fi
        ;;
    status|probe)
        pid_file="${XDG_RUNTIME_DIR:-/tmp}/zenith-inhibit.pid"
        if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
            echo "MANAGED=true INHIBITED=true"
        else
            echo "MANAGED=true INHIBITED=false"
        fi
        ;;
    apply|remove)
        echo "MANAGED=true"
        ;;
    *)
        echo "MANAGED=true"
        ;;
esac
