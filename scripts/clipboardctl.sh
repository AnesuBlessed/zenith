#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Clipboard Helper (cliphist + wl-clipboard + ImageMagick)
# =============================================================================
#  Protocol (consumed by services/ClipboardService.qml):
#    copy <id> | delete <id> | wipe | list
#    open-preview-session                      -> absolute temp directory
#    close-preview-session <dir>
#    thumbnail <id> <format> <bytes> <w> <h> <dir> <out> <maxBytes> <maxDim> <maxPixels> <tw> <th>
#    probe-current <dir> <out> <maxBytes> <maxDim> <maxPixels> <tw> <th>
# =============================================================================
set -euo pipefail

cmd="${1:-}"
id="${2:-}"

have() { command -v "$1" >/dev/null 2>&1; }
magick_bin() { if have magick; then echo magick; elif have convert; then echo convert; else echo ""; fi; }

require_uint() {
    local name="$1" value="$2"
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "clipboardctl: invalid $name '$value'" >&2
        exit 1
    fi
}

case "$cmd" in
    copy|delete)
        [[ "$id" =~ ^[0-9]+$ ]] || { echo "clipboardctl: invalid entry id" >&2; exit 1; }
        line="$(cliphist list | awk -F '\t' -v id="$id" '$1 == id { print; exit }')"
        [[ -n "$line" ]] || { echo "clipboardctl: entry not found" >&2; exit 1; }
        if [[ "$cmd" == "copy" ]]; then
            printf '%s' "$line" | cliphist decode | wl-copy
        else
            printf '%s' "$line" | cliphist delete
        fi
        ;;

    wipe)
        cliphist wipe
        ;;

    list)
        cliphist list
        ;;

    open-preview-session)
        base="${XDG_RUNTIME_DIR:-/tmp}"
        dir="$(mktemp -d "$base/zenith-clipboard.XXXXXX")"
        chmod 700 "$dir"
        printf '%s\n' "$dir"
        ;;

    close-preview-session)
        dir="${2:-}"
        base="${XDG_RUNTIME_DIR:-/tmp}/zenith-clipboard."
        case "$dir" in
            "$base"*) [[ -d "$dir" ]] && rm -rf -- "$dir" ;;
            *) exit 1 ;;
        esac
        ;;

    thumbnail)
        # id format bytes width height dir out maxBytes maxDim maxPixels tw th
        image_format="${3:-}"
        bytes="${4:-0}"
        width="${5:-0}"
        height="${6:-0}"
        dir="${7:-}"
        out="${8:-}"
        max_bytes="${9:-0}"
        max_dim="${10:-0}"
        max_pixels="${11:-0}"
        thumb_w="${12:-0}"
        thumb_h="${13:-0}"

        [[ -z "$id" || -z "$dir" || -z "$out" ]] && { echo "clipboardctl: missing thumbnail arguments" >&2; exit 1; }
        require_uint bytes "$bytes"
        require_uint width "$width"
        require_uint height "$height"
        require_uint maxBytes "$max_bytes"
        require_uint maxDim "$max_dim"
        require_uint maxPixels "$max_pixels"
        require_uint thumbWidth "$thumb_w"
        require_uint thumbHeight "$thumb_h"

        [[ -d "$dir" ]] || { echo "clipboardctl: preview session is gone" >&2; exit 1; }
        if (( bytes > max_bytes || width > max_dim || height > max_dim || width * height > max_pixels )); then
            echo "clipboardctl: image is too large to preview" >&2
            exit 1
        fi
        tool="$(magick_bin)"
        [[ -z "$tool" ]] && { echo "clipboardctl: ImageMagick is required for image previews" >&2; exit 1; }
        tmp="$(mktemp --suffix=.img)"
        cliphist decode "$id" > "$tmp"
        "$tool" "$tmp" -auto-orient -thumbnail "${thumb_w}x${thumb_h}>" "png:$dir/$out"
        rm -f "$tmp"
        ;;

    probe-current)
        dir="${2:-}"
        out="${3:-}"
        max_bytes="${4:-0}"
        max_dim="${5:-0}"
        max_pixels="${6:-0}"
        thumb_w="${7:-0}"
        thumb_h="${8:-0}"
        [[ -z "$dir" || -z "$out" ]] && { echo "clipboardctl: missing probe arguments" >&2; exit 1; }
        [[ -d "$dir" ]] || { echo "clipboardctl: preview session is gone" >&2; exit 1; }

        types="$(wl-paste --list-types 2>/dev/null || true)"
        image_type="$(printf '%s\n' "$types" | grep -m1 '^image/' || true)"
        if [[ -z "$image_type" ]]; then
            echo "kind=empty"
            exit 0
        fi
        tool="$(magick_bin)"
        if [[ -z "$tool" ]]; then
            echo "kind=unsupported"
            exit 0
        fi
        tmp="$(mktemp --suffix=.img)"
        wl-paste --type "$image_type" > "$tmp" 2>/dev/null || true
        if [[ ! -s "$tmp" ]]; then rm -f "$tmp"; echo "kind=empty"; exit 0; fi
        dims="$("$tool" identify -format '%w %h' "$tmp" 2>/dev/null || true)"
        bytes="$(wc -c < "$tmp" | tr -d ' ')"
        width="${dims%% *}"
        height="${dims##* }"
        if [[ -z "$dims" || -z "$width" || -z "$height" ]]; then rm -f "$tmp"; echo "kind=unsupported"; exit 0; fi
        if (( bytes > max_bytes || width > max_dim || height > max_dim || width * height > max_pixels )); then
            rm -f "$tmp"
            echo "kind=unsupported"
            exit 0
        fi
        "$tool" "$tmp" -auto-orient -thumbnail "${thumb_w}x${thumb_h}>" "png:$dir/$out"
        rm -f "$tmp"
        echo "kind=image"
        echo "format=png"
        ;;

    *)
        echo "Usage: clipboardctl.sh {copy|delete|wipe|list|open-preview-session|close-preview-session|thumbnail|probe-current}" >&2
        exit 1
        ;;
esac