-- =============================================================================
--  ZENITH — WINDOW & LAYER RULES (LUA)
-- =============================================================================

-- =====================================================
-- 1. Window Rules
-- =====================================================

-- Mobile Phone File Sharing & Volume Mount Dialogs
hl.window_rule({
    name  = "mobile_transfer_dialogs",
    match = {
        class = "^(thunar|org\\.xfce\\.thunar)$",
        title = "^(File Operation Progress|Device.*|Confirm.*|Properties)$",
    },
    float  = true,
    center = true,
})

-- Wallpaper Shower Gallery (Cinematic Widescreen Window)
hl.window_rule({
    name  = "wallpaper_gallery",
    match = {
        class = "^(org\\.zenith\\.gallery)$",
    },
    float  = true,
    center = true,
    size   = "1280 780",
})

-- Picture-in-Picture Video
hl.window_rule({
    name  = "picture_in_picture",
    match = {
        title = "^(Picture-in-Picture)$",
    },
    float = true,
    pin   = true,
})

-- Settings & System Utilities
hl.window_rule({
    name  = "floating_utilities",
    match = {
        class = "^(pavucontrol|org\\.pulseaudio\\.pavucontrol|blueman-manager|nm-connection-editor|file-roller|org\\.gnome\\.FileRoller|hyprpolkitagent)$",
    },
    float  = true,
    center = true,
    size   = "760 520",
})

-- File Pickers
hl.window_rule({
    name  = "file_pickers",
    match = {
        title = "^(Open File|Open Folder|Save As|Choose Files|File Upload.*)$",
    },
    float  = true,
    center = true,
})

-- =====================================================
-- 2. Layer Shell Rules (0ms Pop-In & Frosted Glass Blur)
-- =====================================================

-- Rofi: Disable animations for instantaneous VBlank pop-in (<5ms)
hl.layer_rule({
    name  = "rofi_zero_anim",
    match = {
        namespace = "^(rofi)$",
    },
    noanim       = true,
    blur         = true,
    ignore_alpha = 0.5,
})

-- Quickshell Dynamic Island: Frosted Glass
hl.layer_rule({
    name  = "quickshell_island",
    match = {
        namespace = "^(quickshell)$",
    },
    blur         = true,
    ignore_alpha = 0.5,
})

-- Mako / Notifications
hl.layer_rule({
    name  = "notifications",
    match = {
        namespace = "^(notifications|mako)$",
    },
    blur         = true,
    ignore_alpha = 0.5,
})
