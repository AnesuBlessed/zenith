-- =============================================================================
--  ZENITH — HARDWARE & ENVIRONMENT (LUA)
-- =============================================================================

-- Wayland & XDG Integration
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Toolkit Wayland Enforcement
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- Qt Wayland Optimization
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- Cursor Defaults
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Input Devices (Touchpad, Gestures, Mouse)
hl.config({
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        sensitivity = 0,

        touchpad = {
            natural_scroll = true,
            tap_to_click   = true,
            drag_lock      = false,
        },
    },

    gestures = {
        workspace_swipe = true,
        workspace_swipe_fingers = 3,
        workspace_swipe_distance = 250,
    },
})

return {
    vfr  = true,
    blur = true,
}
