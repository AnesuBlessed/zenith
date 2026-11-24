#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Theme Export (palette.json -> portable consumer files)
# =============================================================================
#  Protocol (consumed by services/ThemeExportService.qml):
#    export-theme.sh <palettePath> <dark|light> <exportDir> <hyprlockEnabled>
# =============================================================================
set -euo pipefail

palette="${1:-}"
mode="${2:-dark}"
export_dir="${3:-}"
hyprlock="${4:-false}"

[[ -n "$palette" && -f "$palette" ]] || { echo "export-theme: palette not found: $palette" >&2; exit 1; }
[[ -n "$export_dir" ]] || { echo "export-theme: missing export directory" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "export-theme: jq is required" >&2; exit 1; }
[[ "$mode" == "light" ]] || mode="dark"

mkdir -p "$export_dir"

group="$(jq -c --arg m "$mode" '.[$m] // .dark // {}' "$palette")"
token() { printf '%s' "$group" | jq -r --arg k "$1" '.[$k] // "#a899e6"'; }

hex_rgb() {
    local hex="${1#\#}"
    if [[ ${#hex} -ne 6 ]]; then printf 'rgb(168, 153, 230)'; return; fi
    printf 'rgb(%d, %d, %d)' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

accent="$(token primary)"
surface="$(token surface)"
text="$(token onSurface)"
container="$(token surfaceContainer)"
outline="$(token outline)"

cat > "$export_dir/colors.conf" <<EOF
# Zenith theme export (mode: $mode) — generated, do not edit.
\$accent = $(hex_rgb "$accent")
\$base   = $(hex_rgb "$surface")
\$surface = $(hex_rgb "$container")
\$text   = $(hex_rgb "$text")
\$muted  = $(hex_rgb "$outline")
EOF

cat > "$export_dir/hyprland-colors.lua" <<EOF
return {
    accent        = "0xff${accent#\#}",
    bg            = "0xff${surface#\#}",
    fg            = "0xff${text#\#}",
    surface       = "0xff${container#\#}",
}
EOF

jq -S . "$palette" > "$export_dir/palette.json"
printf '%s\n' "$mode" > "$export_dir/mode"

if [[ "$hyprlock" == "true" ]]; then
    "${ZENITH_ROOT:-$HOME/.config/zenith}/scripts/manage-theme-integration.sh" hyprlock refresh >/dev/null 2>&1 || true
fi

echo "EXPORTED=$export_dir"