#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Notes Control Helper (Zero-Python POSIX Shell)
#  Called by NotesService.qml for CRUD note operations.
#  Protocol: JSON output on stdout, errors on stderr, exit 1 on failure.
#  Commands: list | create | save <id> | delete <id>
# =============================================================================
set -euo pipefail

NOTES_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zenith/notes"
mkdir -p "$NOTES_DIR"

CMD="${1:-list}"
ID="${2:-}"

# ── helpers ──────────────────────────────────────────────────────────────────

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

new_id() {
    # 8-hex random id — unique enough for local notes
    if command -v od >/dev/null 2>&1; then
        od -A n -t x1 -N 4 /dev/urandom | tr -d ' \n'
    else
        printf '%08x' $((RANDOM * RANDOM))
    fi
}

json_escape() {
    # Escape a string value for embedding in JSON
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' \
        | awk '{printf "%s\\n", $0}' | head -c -2
    # Note: strip trailing \n added by awk
}

note_to_json() {
    local id="$1" file="$2"
    local title content updated
    title="$(sed -n '1p' "$file")"
    content="$(tail -n +3 "$file")"
    updated="$(stat -c '%Y' "$file" 2>/dev/null | xargs -I{} date -u -d @{} +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || now_iso)"
    printf '{"id":"%s","title":"%s","content":"%s","updated":"%s"}' \
        "$id" "$(json_escape "$title")" "$(json_escape "$content")" "$updated"
}

# ── commands ─────────────────────────────────────────────────────────────────

case "$CMD" in

    list)
        printf '{"notes":['
        first=1
        for f in "$NOTES_DIR"/*.note 2>/dev/null; do
            [[ -f "$f" ]] || continue
            id="$(basename "$f" .note)"
            [[ $first -eq 0 ]] && printf ','
            note_to_json "$id" "$f"
            first=0
        done
        printf ']}'
        ;;

    create)
        id="$(new_id)"
        file="$NOTES_DIR/$id.note"
        printf 'New Note\n\n' > "$file"
        note_to_json "$id" "$file"
        ;;

    save)
        [[ -z "$ID" ]] && { echo '{"error":"missing note id"}' >&2; exit 1; }
        file="$NOTES_DIR/$ID.note"
        # Read JSON payload from stdin: {"title":"...","content":"..."}
        payload="$(cat)"
        title="$(printf '%s' "$payload" | sed 's/.*"title"[[:space:]]*:[[:space:]]*"\(.*\)","content.*/\1/' | sed 's/\\n/\n/g; s/\\t/\t/g')"
        content="$(printf '%s' "$payload" | sed 's/.*"content"[[:space:]]*:[[:space:]]*"\(.*\)"[[:space:]]*}/\1/' | sed 's/\\n/\n/g; s/\\t/\t/g')"
        printf '%s\n\n%s\n' "$title" "$content" > "$file"
        note_to_json "$ID" "$file"
        ;;

    delete)
        [[ -z "$ID" ]] && { echo '{"error":"missing note id"}' >&2; exit 1; }
        file="$NOTES_DIR/$ID.note"
        [[ -f "$file" ]] && rm -f "$file"
        printf '{}'
        ;;

    *)
        printf '{"error":"unknown command: %s"}' "$CMD" >&2
        exit 1
        ;;
esac
