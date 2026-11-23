#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Clipboard Control Helper
#  Called by ClipboardService.qml for copy / delete / wipe operations.
#  Protocol: clipboardctl.sh <copy|delete|wipe> [entry-id]
# =============================================================================
set -euo pipefail

CMD="${1:-}"
ID="${2:-}"

case "$CMD" in
    copy)
        [[ -z "$ID" ]] && { echo "clipboardctl: missing entry id" >&2; exit 1; }
        cliphist decode "$ID" | wl-copy
        ;;
    delete)
        [[ -z "$ID" ]] && { echo "clipboardctl: missing entry id" >&2; exit 1; }
        cliphist delete-query "$ID" 2>/dev/null || cliphist delete "$ID" 2>/dev/null || true
        ;;
    wipe)
        cliphist wipe
        ;;
    list)
        # Output: <id>\t<preview> — cliphist already does this
        cliphist list
        ;;
    *)
        echo "Usage: clipboardctl.sh <copy|delete|wipe|list> [id]" >&2
        exit 1
        ;;
esac
