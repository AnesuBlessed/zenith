-- =============================================================================
--  ZENITH — HYPRLAND MASTER CONFIGURATION (LUA)
-- =============================================================================
--  - Single Responsibility: Each module has exactly one isolated role
--  - Event-driven, zero runtime bloat, VFR enabled (0 FPS when static)
--  - High performance & low-latency compositor settings
-- =============================================================================

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local config_hypr = (os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")) .. "/hypr/"
package.path = script_dir .. "?.lua;" .. config_hypr .. "?.lua;" .. package.path

-- Invalidate component cache so re-evaluating hyprland.lua cleanly reloads all modules
package.loaded["paths"]     = nil
package.loaded["colors"]    = nil
package.loaded["monitors"]  = nil
package.loaded["hardware"]  = nil
package.loaded["autostart"] = nil
package.loaded["looknfeel"] = nil
package.loaded["keybinds"]  = nil
package.loaded["rules"]     = nil

-- Modular Component Inclusions
require("paths")
require("colors")
require("monitors")
require("hardware")
require("autostart")
require("looknfeel")
require("keybinds")
require("rules")
