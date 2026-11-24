#!/usr/bin/env bash
# =============================================================================
#  ZENITH — System Sensor Paths Helper (POSIX Shell)
# =============================================================================
set -euo pipefail

# Output detected hardware sensor thermal & battery sysfs paths in JSON format
temp_path=""
for p in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp1_input; do
    if [[ -r "$p" ]]; then
        temp_path="$p"
        break
    fi
done

bat_path=""
for p in /sys/class/power_supply/BAT*/capacity; do
    if [[ -r "$p" ]]; then
        bat_path="$(dirname "$p")"
        break
    fi
done

printf '{"thermal":"%s","battery":"%s"}\n' "$temp_path" "$bat_path"
