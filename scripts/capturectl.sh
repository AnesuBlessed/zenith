#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Screen Capture & Recording Helper
# =============================================================================
#  Protocol (consumed by services/CaptureService.qml):
#    probe                          -> SCREENSHOT/CLIPBOARD/RECORDING/REGION=ready
#    screenshot <mode> <monitor> <output>
#      mode:   full | monitor | region | active
#      output: save | copy | both
#      -> PATH= SAVED=true|false COPIED=true|false  (exit 2 when cancelled)
#    prepare-recording <monitor|region> <monitor>
#      -> PATH= TARGET= [REGION=]                   (exit 2 when cancelled)
# =============================================================================
set -euo pipefail

cmd="${1:-}"
shots_dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
recs_dir="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
stamp="$(date +%Y-%m-%d_%H-%M-%S)"

have() { command -v "$1" >/dev/null 2>&1; }

notify() {
    if have notify-send; then notify-send -a Zenith "$1" "$2" >/dev/null 2>&1 || true; fi
}

case "$cmd" in
    probe)
        if have grim && have wl-copy; then echo "SCREENSHOT=ready"; else echo "SCREENSHOT=missing"; fi
        if have wl-copy; then echo "CLIPBOARD=ready"; else echo "CLIPBOARD=missing"; fi
        if have wf-recorder; then echo "RECORDING=ready"; else echo "RECORDING=missing"; fi
        if have slurp && have grim; then echo "REGION=ready"; else echo "REGION=missing"; fi
        ;;

    screenshot)
        mode="${2:-full}"
        monitor="${3:-}"
        output="${4:-both}"
        mkdir -p "$shots_dir"
        file="$shots_dir/Screenshot_${stamp}.png"
        args=()
        case "$mode" in
            region)
                geometry="$(slurp 2>/dev/null || true)"
                if [[ -z "$geometry" ]]; then exit 2; fi
                args=(-g "$geometry")
                ;;
            monitor)
                if [[ -n "$monitor" ]]; then args=(-o "$monitor"); fi
                ;;
            full) args=() ;;
            active)
                mon="$(hyprctl activeworkspace -j 2>/dev/null | sed -n 's/.*"monitor": "\([^"]*\)".*/\1/p')"
                if [[ -n "$mon" ]]; then args=(-o "$mon"); fi
                ;;
            *) echo "capturectl: unknown screenshot mode '$mode'" >&2; exit 1 ;;
        esac
        if [[ "$output" == "copy" ]]; then
            cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/zenith"
            mkdir -p "$cache_root"
            tmp="$cache_root/last-screenshot.png"
        else
            tmp="$(mktemp --suffix=.png)"
        fi
        if ! grim "${args[@]}" "$tmp" 2>/dev/null; then
            rm -f "$tmp"
            exit 2
        fi
        saved=false
        copied=false
        if [[ "$output" == "save" || "$output" == "both" ]]; then
            mv -f "$tmp" "$file"
            tmp="$file"
            saved=true
        fi
        if [[ "$output" == "copy" || "$output" == "both" ]]; then
            if wl-copy < "$tmp" 2>/dev/null; then copied=true; fi
        fi
        [[ -f "$file" ]] || file="$tmp"
        printf 'PATH=%s\nSAVED=%s\nCOPIED=%s\n' "$file" "$saved" "$copied"
        notify "Screenshot" "$(basename "$file")"
        ;;

    prepare-recording)
        mode="${2:-monitor}"
        monitor="${3:-}"
        mkdir -p "$recs_dir"
        file="$recs_dir/Recording_${stamp}.mp4"
        target="$monitor"
        region=""
        if [[ "$mode" == "region" ]]; then
            region="$(slurp 2>/dev/null || true)"
            if [[ -z "$region" ]]; then exit 2; fi
            if [[ -z "$target" ]]; then
                target="$(hyprctl monitors -j 2>/dev/null | sed -n 's/.*"name": "\([^"]*\)".*/\1/p' | head -1)"
            fi
        fi
        if [[ -z "$target" ]]; then
            echo "capturectl: no monitor available for recording" >&2
            exit 1
        fi
        printf 'PATH=%s\nTARGET=%s\nREGION=%s\n' "$file" "$target" "$region"
        ;;

    open-screenshots)
        mkdir -p "$shots_dir"
        xdg-open "$shots_dir" >/dev/null 2>&1 || true
        ;;

    *)
        echo "Usage: capturectl.sh {probe|screenshot|prepare-recording|open-screenshots}" >&2
        exit 1
        ;;
esac