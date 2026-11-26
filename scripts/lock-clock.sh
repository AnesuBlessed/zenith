#!/bin/sh
# lock-clock.sh — two-tone clock markup for hyprlock (Pango spans).
# "12" stays near-white, ":06" carries the mint accent, matching the mock.
H=$(date +%H)
M=$(date +%M)
printf '<span foreground="#e4ebf5">%s</span><span foreground="#a5d8c8">%s</span>' \
    "$H" ":$M"
