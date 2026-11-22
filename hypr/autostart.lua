-- =============================================================================
--  ZENITH — AUTOSTART DAEMONS & SERVICES (LUA)
-- =============================================================================
local paths = require("paths")

-- 1. Sub-millisecond Terminal Client-Server Daemon
hl.exec_once("foot --server")

-- 2. Quickshell Dynamic Island
hl.exec_once("quickshell -s " .. paths.root .. "/shell.qml")

-- 3. Wallpaper Transition Daemon & Pre-Bake Initial Crops
hl.exec_once("swww-daemon")
hl.exec_once(paths.bin("zenith-native") .. " align")

-- 4. Wayland Clipboard History Daemons
hl.exec_once("wl-paste --type text --watch cliphist store")
hl.exec_once("wl-paste --type image --watch cliphist store")

-- 5. Notification Center
hl.exec_once("mako")

-- 6. Polkit Authentication Agent
hl.exec_once("/usr/lib/polkit-kde-authentication-agent-1 || /usr/lib/hyprpolkitagent")
