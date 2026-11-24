-- =============================================================================
--  ZENITH — AUTOSTART DAEMONS & SERVICES (LUA)
-- =============================================================================
local paths = require("paths")

hl.on("hyprland.start", function()
    -- 1. Sub-millisecond Terminal Client-Server Daemon
    hl.exec_cmd("foot --server")

    -- 2. Quickshell Dynamic Island (using repo path for clean relative imports)
    hl.exec_cmd("quickshell -p " .. paths.quote(paths.root))

    -- 3. Wallpaper + palette transaction (swww, Hyprland colors, foot, rofi)
    --    `ensure` re-applies the last wallpaper or picks the first one, and
    --    fills in the palette on a fresh install.
    local ensure = "sleep 1.5 && " .. paths.quote(paths.root .. "/build/zenith-native") .. " wallpaper ensure"
    hl.exec_cmd("bash -c " .. paths.quote(ensure))

    -- 4. Idle management (lock, DPMS, suspend)
    hl.exec_cmd("hypridle")

    -- 5. Wayland Clipboard History Daemons
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- 6. Polkit Authentication Agent
    hl.exec_cmd("bash -c '/usr/lib/polkit-kde-authentication-agent-1 || /usr/lib/hyprpolkitagent'")
end)