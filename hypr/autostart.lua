-- =============================================================================
--  ZENITH — AUTOSTART DAEMONS & SERVICES (LUA)
-- =============================================================================
local paths = require("paths")

hl.on("hyprland.start", function()
    -- 1. Sub-millisecond Terminal Client-Server Daemon
    hl.exec_cmd("foot --server")

    -- 2. Quickshell Dynamic Island
    hl.exec_cmd("quickshell -s " .. paths.root .. "/shell.qml")

    -- 3. Wallpaper Transition Daemon & initial wallpaper
    hl.exec_cmd("swww-daemon")
    -- Set a wallpaper on first boot (swww-daemon needs ~1s to initialize)
    hl.exec_cmd("bash -c 'sleep 1.5 && WALL=$(ls " .. paths.root .. "/wallpapers/*/*.{png,jpg,jpeg,PNG,JPG} 2>/dev/null | head -1) && [ -n \"$WALL\" ] && swww img \"$WALL\" --transition-type fade --transition-duration 1'")
    hl.exec_cmd(paths.bin("zenith-native") .. " align")

    -- 4. Wayland Clipboard History Daemons
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- 5. Polkit Authentication Agent
    hl.exec_cmd("bash -c '/usr/lib/polkit-kde-authentication-agent-1 || /usr/lib/hyprpolkitagent'")
end)
