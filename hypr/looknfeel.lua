-- =============================================================================
--  ZENITH — LOOK & FEEL AND PERFORMANCE COMPOSITION (LUA)
-- =============================================================================
local colors   = require("colors")
local hardware = require("hardware")

hl.config({
    general = {
        gaps_in          = 6,
        gaps_out         = 10,
        border_size      = 2,

        col = {
            active_border   = { colors = { colors.accent, colors.surface }, angle = 45 },
            inactive_border = colors.border_dark,
        },

        layout           = "dwindle",
        resize_on_border = true,
        allow_tearing    = false,
    },

    decoration = {
        rounding         = 12,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = false,
        },

        -- Dual-pass optimized blur: ~70% lower GPU shader load than 4-pass Gaussian
        blur = {
            enabled           = (hardware.blur ~= false),
            size              = 5,
            passes            = 2,
            new_optimizations = true,
            ignore_opacity    = true,
            xray              = false,
        },
    },

    debug = {
        vfr = (hardware.vfr ~= false), -- Variable Frame Rate (0 FPS when static)
    },

    dwindle = {
        preserve_split = true,
        smart_split    = false,
        smart_resizing = true,
    },

    misc = {
        vrr                      = 1, -- Adaptive Sync enabled
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        mouse_move_enables_dpms  = true,
        key_press_enables_dpms   = true,
        focus_on_activate        = true,
        allow_session_lock_restore = true,
    },

    render = {
        direct_scanout = 1, -- 0ms bypass for fullscreen video and games
    },

    cursor = {
        no_hardware_cursors  = false,
        enable_hyprcursor    = true,
        sync_gsettings_theme = true,
    },
})

-- Snappy, low-latency kinetic spring curve (~120ms)
hl.curve("microSnap", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })

hl.animation({ leaf = "windows",    enabled = true, speed = 1.4, bezier = "microSnap", style = "popin 85%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.2, bezier = "microSnap", style = "popin 85%" })
hl.animation({ leaf = "border",     enabled = true, speed = 1.0, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 1.0, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.4, bezier = "microSnap", style = "slide" })
hl.animation({ leaf = "layers",     enabled = true, speed = 1.2, bezier = "microSnap", style = "fade" })
