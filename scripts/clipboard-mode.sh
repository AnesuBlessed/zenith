#!/usr/bin/env bash
set -euo pipefail
ZENITH_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ -x "$ZENITH_ROOT/build/zenith-native" ]]; then
    exec "$ZENITH_ROOT/build/zenith-native" clipboard-mode "$@"
else
    exec zenith-native clipboard-mode "$@"
fi
