-- =============================================================================
--  ZENITH — AUTOSTART DAEMONS & SERVICES (LUA)
-- =============================================================================
local paths = require("paths")

hl.on("hyprland.start", function()
    -- 1. Sub-millisecond Terminal Client-Server Daemon
    hl.exec_cmd("foot --server")

    -- 2. Quickshell Dynamic Island
    hl.exec_cmd("quickshell -s " .. paths.root .. "/shell.qml")

    -- 3. Wallpaper Transition Daemon & Pre-Bake Initial Crops
    hl.exec_cmd("swww-daemon")
    hl.exec_cmd(paths.bin("zenith-native") .. " align")

    -- 4. Wayland Clipboard History Daemons
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- 5. Polkit Authentication Agent
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1 || /usr/lib/hyprpolkitagent")
end)
