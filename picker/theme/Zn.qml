pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Zenith picker theme + backend bridge.
//
// Reads the same palette file as the shell (written atomically by
// `zenith-native`), so the picker always matches the running theme. All
// wallpaper mutations go through `zenith-native`, which owns swww, the
// palette, the launcher crops and the state file.
QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
        || (home + "/.local/state")
    readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME")
        || (home + "/.cache")
    readonly property string repoRoot: {
        const env = Quickshell.env("ZENITH_ROOT")
        if (env)
            return env
        return Quickshell.shellDir + "/.."
    }
    readonly property string nativeBinary: repoRoot + "/build/zenith-native"
    readonly property string palettePath: stateHome + "/zenith/palette.json"
    readonly property string settingsPath: (Quickshell.env("XDG_CONFIG_HOME")
        || (home + "/.config")) + "/zenith/settings.json"
    // Wallpaper options mirrored from the shell settings so picker applies
    // behave exactly like applies from the in-shell wallpaper page.
    readonly property var validTransitions: [
        "fade", "slide", "wipe", "wave", "expand", "contract",
        "spotlight", "random"
    ]
    property string settingsTransition: "fade"
    property real settingsDuration: 0.9
    property bool settingsReducedMotion: false
    property bool settingsTargetAll: false
    // Flat picker symlink recorded by `wallpaper set`, so active-card
    // comparisons match the paths FolderListModel exposes. The raw canonical
    // path remains in state/current_wallpaper for every other consumer.
    readonly property string currentWallpaperPath: wallpaperDir + "/.current"
    readonly property string wallpaperDir: cacheHome + "/zenith/picker"
    readonly property string wallpaperFolder: "file://" + wallpaperDir
    readonly property string wallpaperBase: "file://" + wallpaperDir + "/"
    readonly property string thumbDir: cacheHome + "/zenith/thumbs"
    readonly property string thumbBase: "file://" + thumbDir + "/"

    property var palette: ({})
    property bool dark: true
    property bool thumbsRunning: false

    readonly property var tokens: dark ? (palette.dark || ({})) : (palette.light || ({}))
    readonly property color fallback: "#a899e6"
    readonly property color accent: tokens.primary || fallback
    readonly property color accentText: tokens.onPrimary || "#1b1226"
    readonly property color accentContainer: tokens.primaryContainer || "#46417f"
    readonly property color bg: tokens.surface || "#121217"
    readonly property color surface: tokens.surfaceContainer || "#202027"
    readonly property color surfaceHigh: tokens.surfaceContainerHigh || "#2a2931"
    readonly property color text: tokens.onSurface || "#e6e1e9"
    readonly property color muted: tokens.onSurfaceVariant || "#c9c5cf"
    readonly property color outline: tokens.outlineVariant || "#48464f"
    readonly property color scrim: dark ? "#05070a" : "#e9e5ee"

    property FileView paletteFile: FileView {
        path: root.palettePath
        watchChanges: true
        blockLoading: true
        preload: true
        printErrors: false
        onLoaded: root.load(text())
        onFileChanged: reload()
    }

    function load(raw: string): void {
        try {
            const parsed = JSON.parse(raw)
            root.palette = parsed
            root.dark = parsed.mode !== "light"
        } catch (error) {
            console.warn("Zenith picker: palette unreadable:", error)
        }
    }

    function apply(path: string): void {
        if (!path)
            return
        // Detached: the picker quits immediately after this call, and the
        // wallpaper transaction (swww + palette + crops + hyprctl) must
        // outlive the short-lived picker process.
        const args = [nativeBinary, "wallpaper", "set", path,
            "--transition", settingsTransition,
            "--duration", settingsDuration.toFixed(1)]
        if (settingsTargetAll)
            args.push("--monitor", "all")
        if (settingsReducedMotion)
            args.push("--reduced-motion")
        Quickshell.execDetached(args)
    }

    function loadSettings(raw: string): void {
        try {
            const parsed = JSON.parse(raw || "{}")
            const wallpaper = parsed?.wallpaper || {}
            settingsTransition = validTransitions.includes(wallpaper.transition)
                ? wallpaper.transition : "fade"
            const duration = Number(wallpaper.transitionDuration)
            settingsDuration = Number.isFinite(duration)
                ? Math.max(0.3, Math.min(2.5, duration)) : 0.9
            settingsReducedMotion =
                (parsed?.appearance?.reducedMotion === true)
                || (wallpaper.reducedMotion === true)
            settingsTargetAll = wallpaper.target === "all"
        } catch (error) {
            console.warn("Zenith picker: settings unreadable:", error)
        }
    }

    property FileView settingsFile: FileView {
        path: root.settingsPath
        watchChanges: true
        blockLoading: true
        preload: true
        printErrors: false
        onLoaded: root.loadSettings(text())
        onFileChanged: reload()
    }

    function generateThumbs(): void {
        if (thumbsRunning)
            return
        thumbsRunning = true
        thumbsProcess.command = [nativeBinary, "wallpaper", "thumbs"]
        thumbsProcess.running = true
    }

    property Process thumbsProcess: Process {
        onExited: root.thumbsRunning = false
    }
}