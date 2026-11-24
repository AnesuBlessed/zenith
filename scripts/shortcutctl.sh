#!/usr/bin/env bash
# =============================================================================
#  ZENITH — Shortcut Helper (POSIX Shell)
# =============================================================================
set -euo pipefail

# Echo available user shortcuts
cat << 'EOF'
[
  {"combo": "SUPER + T", "description": "Foot Terminal"},
  {"combo": "SUPER + A", "description": "App Launcher"},
  {"combo": "SUPER + C", "description": "Clipboard Manager"},
  {"combo": "SUPER + W", "description": "Wallpaper Gallery"},
  {"combo": "SUPER + N", "description": "Island Control Center"},
  {"combo": "SUPER + Q", "description": "Close Window"},
  {"combo": "SUPER + M", "description": "Fullscreen Window"},
  {"combo": "SUPER + E", "description": "File Manager (Thunar)"},
  {"combo": "SUPER + B", "description": "Web Browser (Firefox)"},
  {"combo": "SUPER + O", "description": "Code Editor (Codium)"},
  {"combo": "SUPER + Escape", "description": "Power Menu"},
  {"combo": "Print", "description": "Region Screenshot"}
]
EOF
