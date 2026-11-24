#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Screen Capture & Recording Helper (POSIX Shell)
# =============================================================================
set -euo pipefail

cmd="${1:-}"
save_dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$save_dir"
timestamp="$(date +%Y-%m-%d_%H-%M-%S)"

case "$cmd" in
    probe)
        printf "SCREENSHOT=ready\nCLIPBOARD=ready\nRECORDING=ready\nREGION=ready\n"
        ;;
    screenshot-screen)
        file="$save_dir/Screenshot_${timestamp}.png"
        grim "$file"
        wl-copy < "$file"
        notify-send -a "Zenith" -i "$file" "Screenshot Taken" "Saved to $file"
        ;;
    screenshot-window|screenshot-region)
        file="$save_dir/Screenshot_${timestamp}.png"
        grim -g "$(slurp)" "$file"
        wl-copy < "$file"
        notify-send -a "Zenith" -i "$file" "Region Screenshot" "Saved to $file"
        ;;
    record-toggle)
        if pidof wf-recorder >/dev/null; then
            pkill -INT wf-recorder
            notify-send -a "Zenith" "Screen Recording" "Recording stopped and saved."
        else
            rec_file="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings/Recording_${timestamp}.mp4"
            mkdir -p "$(dirname "$rec_file")"
            notify-send -a "Zenith" "Screen Recording" "Recording started..."
            wf-recorder -f "$rec_file" &
        fi
        ;;
    status)
        if pidof wf-recorder >/dev/null; then
            echo "recording"
        else
            echo "idle"
        fi
        ;;
    *)
        echo "Usage: capturectl.sh {screenshot-screen|screenshot-region|record-toggle|status}" >&2
        exit 1
        ;;
esac
