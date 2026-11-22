-- =============================================================================
--  ZENITH — MONITORS CONFIGURATION (LUA)
-- =============================================================================
-- Hardware-agnostic auto configuration for laptops, desktops & multi-monitors.

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1.0,
})

local state_dir = os.getenv("ZENITH_STATE") or ((os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")) .. "/zenith")
local saved_monitors = state_dir .. "/monitors.lua"
local f = io.open(saved_monitors, "r")
if f then
    f:close()
    pcall(dofile, saved_monitors)
end
