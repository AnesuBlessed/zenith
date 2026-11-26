pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Sole owner of the wallpaper + palette transaction.
//
// Every mutation goes through `build/zenith-native`, which applies the
// wallpaper with swww, regenerates the Material palette, rewrites the
// Hyprland / foot / rofi consumers, refreshes the launcher crops and records
// the current selection. The QML side never shells out to ad-hoc helpers, so
// there is exactly one implementation of "apply a wallpaper".
QtObject {
    id: root

    property var wallpapers: []
    property string currentWallpaper: ""
    property string pendingWallpaper: ""
    property string pendingScheme: ""
    property string previousScheme: ""
    property string pendingThemeSourceMode: ""
    property string pendingThemeSourceColor: ""
    property bool pendingRememberCustom: false
    property bool loading: false
    property bool applying: false
    property bool backendAvailable: false
    property string backendState: "starting"
    property string backendDetail: "Checking the swww renderer…"
    property string operationState: "idle"
    property string operationKind: ""
    property string operationOutput: ""
    property string operationError: ""
    property string errorMessage: ""
    property bool paletteAvailable: Theme.generatedAvailable

    readonly property string helperPath:
        Quickshell.shellDir + "/build/zenith-native"
    readonly property var searchPaths: Config.wallpaper.directories.map(path =>
        path.startsWith("/") ? path : Quickshell.env("HOME") + "/" + path)
    readonly property string currentName: displayName(currentWallpaper)
    readonly property bool busy: operationProcess.running
    readonly property string statusLabel: errorMessage
        || (backendState !== "ready" ? backendDetail
        : currentWallpaper ? currentName : "No wallpaper selected")

    signal wallpaperApplied(string path, bool paletteUpdated)

    function displayName(path: string): string {
        const name = path.substring(path.lastIndexOf("/") + 1)
            .replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ")
        return name.replace(/\b\w/g, character => character.toUpperCase())
    }

    function imageSource(path: string): string {
        return path ? "file://" + path.split("/").map(encodeURIComponent)
            .join("/") : ""
    }

    function filterWallpapers(query: string): var {
        const normalized = query.trim().toLowerCase()
        return !normalized ? wallpapers : wallpapers.filter(item =>
            item.name.toLowerCase().includes(normalized)
                || item.path.toLowerCase().includes(normalized))
    }

    function setTarget(target: string): bool {
        return SettingsStore.setWallpaperTarget(target)
    }

    function setGalleryColumns(columns: int): bool {
        return SettingsStore.setWallpaperGalleryColumns(columns)
    }

    function setTransition(transition: string): bool {
        return SettingsStore.setWallpaperTransition(transition)
    }

    // Picker layout selection lives in picker/config.json (active_layout),
    // which the standalone picker watches, so changes apply without a restart.
    readonly property var pickerLayouts: [
        "shell-coverflow.qml",
        "shell-floating.qml",
        "shell-grid-view.qml"
    ]
    property string pickerLayout: "shell-floating.qml"

    function pickerLayoutLabel(name: string): string {
        return name.replace(/\\.qml$/, "").replace(/^shell-/, "")
            .split("-")
            .map(part => part.charAt(0).toUpperCase() + part.slice(1))
            .join(" ")
    }

    property FileView pickerConfigFile: FileView {
        path: Quickshell.shellDir + "/picker/config.json"
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        preload: true
        printErrors: false
        onLoaded: root.readPickerConfig(text())
    }

    function readPickerConfig(raw: string): void {
        try {
            const parsed = JSON.parse(raw || "{}")
            const layout = String(parsed?.active_layout || "")
            if (pickerLayouts.includes(layout))
                pickerLayout = layout
        } catch (error) {
            console.warn("Zenith could not read picker config:", error)
        }
    }

    function setPickerLayout(name: string): bool {
        if (!pickerLayouts.includes(name) || name === pickerLayout)
            return false
        try {
            const parsed = JSON.parse(pickerConfigFile.text() || "{}")
            parsed.active_layout = name
            pickerConfigFile.setText(JSON.stringify(parsed, null, 2) + "\n")
            pickerLayout = name
            return true
        } catch (error) {
            console.warn("Zenith could not update the picker layout:", error)
            return false
        }
    }

    function setTransitionDuration(duration: real): bool {
        return SettingsStore.setWallpaperTransitionDuration(duration)
    }

    function resetPreferences(): void {
        SettingsStore.resetWallpaper()
    }

    function parseStatus(text: string): void {
        for (const line of text.split("\n")) {
            if (line.startsWith("CURRENT="))
                currentWallpaper = line.substring(8).trim()
            if (!line.startsWith("STATE="))
                continue
            backendState = line.substring(6).trim()
            backendAvailable = backendState === "ready"
            if (backendState === "ready")
                backendDetail = "swww renderer ready"
            else if (backendState === "starting")
                backendDetail = "Starting the swww renderer…"
            else if (backendState === "missing")
                backendDetail = "swww is required for Zenith wallpapers (sudo pacman -S swww)"
            else
                backendDetail = "swww is unavailable; Retry to check again"
        }
    }

    function beginOperation(kind: string, command: var): bool {
        if (operationProcess.running)
            return false
        operationKind = kind
        operationOutput = ""
        operationError = ""
        operationProcess.command = command
        operationProcess.running = true
        return true
    }

    function refresh(): void {
        if (discoveryProcess.running)
            return
        loading = true
        discoveryProcess.command = [helperPath, "wallpaper", "list"]
        discoveryProcess.running = true
    }

    function bootstrap(manual: bool): void {
        if (busy || applying)
            return
        backendState = manual ? "starting" : "starting"
        backendDetail = manual ? "Re-checking the swww renderer…"
            : "Starting the swww renderer…"
        errorMessage = ""
        beginOperation("probe", [helperPath, "wallpaper", "probe"])
    }

    function retry(): void {
        bootstrap(true)
    }

    function applyWallpaper(path: string, monitorName: string): bool {
        if (busy || applying || !wallpapers.some(item => item.path === path))
            return false
        if (Config.wallpaper.target === "all")
            monitorName = "all"
        pendingWallpaper = path
        applying = true
        errorMessage = ""
        operationState = "applying"
        return beginOperation("apply", [helperPath, "wallpaper", "set", path,
            "--transition", Config.wallpaper.transition,
            "--duration", String(Config.wallpaper.transitionDuration),
            "--monitor", monitorName || "",
            Config.appearance.reducedMotion ? "--reduced-motion" : ""].filter(
                argument => argument.length > 0))
    }

    function changeScheme(scheme: string): void {
        if (scheme === Config.wallpaper.scheme || busy || applying
                || (Config.appearance.themeSourceMode === "wallpaper"
                    && !currentWallpaper))
            return
        pendingScheme = scheme
        previousScheme = Config.wallpaper.scheme
        if (!SettingsStore.setScheme(scheme)) {
            pendingScheme = ""
            previousScheme = ""
            return
        }
        errorMessage = ""
        operationState = "changingScheme"
        if (Config.appearance.themeSourceMode === "color") {
            beginOperation("colorScheme", [helperPath, "theme", "color",
                Config.appearance.themeSourceColor])
        } else {
            beginOperation("scheme", [helperPath, "theme", "refresh"])
        }
    }

    function refreshPaletteForMode(): bool {
        if (busy || applying)
            return false
        errorMessage = ""
        operationState = "changingMode"
        if (Config.appearance.themeSourceMode === "color") {
            return beginOperation("mode", [helperPath, "theme", "color",
                Config.appearance.themeSourceColor])
        }
        return beginOperation("mode", [helperPath, "theme", "refresh"])
    }

    function changeThemeSource(mode: string, color: string,
            rememberCustom: bool): bool {
        const normalized = SettingsStore.normalizedThemeColor(color)
        if (busy || applying
                || (mode === "wallpaper" && !currentWallpaper)
                || (mode !== "wallpaper" && mode !== "color")
                || (mode === "color" && !normalized))
            return false
        if (mode === Config.appearance.themeSourceMode
                && (mode === "wallpaper"
                    || normalized === Config.appearance.themeSourceColor)) {
            if (mode === "color" && rememberCustom)
                SettingsStore.setThemeSourceColor(normalized, true)
            return false
        }
        errorMessage = ""
        operationState = "changingThemeSource"
        pendingThemeSourceMode = mode
        pendingThemeSourceColor = normalized
        pendingRememberCustom = rememberCustom
        if (mode === "color") {
            return beginOperation("themeSource", [helperPath, "theme", "color",
                normalized])
        }
        return beginOperation("themeSource", [helperPath, "theme", "refresh"])
    }

    function finishOperation(exitCode: int): void {
        const kind = operationKind
        const output = operationOutput
        const detail = operationError.trim()
        parseStatus(output)
        operationKind = ""

        if (kind === "probe") {
            operationState = "idle"
            if (backendState !== "ready")
                errorMessage = exitCode === 0 ? "" : (detail || backendDetail)
            return
        }

        if (kind === "apply") {
            applying = false
            const committed = exitCode === 0 && output.includes("COMMITTED=true")
            if (committed) {
                const applied = pendingWallpaper
                currentWallpaper = applied
                pendingWallpaper = ""
                paletteAvailable = true
                errorMessage = ""
                operationState = "idle"
                wallpaperApplied(applied, output.includes("PALETTE=updated"))
            } else {
                pendingWallpaper = ""
                errorMessage = detail || "Wallpaper could not be applied"
                operationState = "idle"
                recoveryTimer.restart()
            }
            return
        }

        if (kind === "scheme" || kind === "colorScheme") {
            const committed = exitCode === 0 && output.includes("PALETTE=updated")
            if (committed) {
                paletteAvailable = true
                errorMessage = ""
                wallpaperApplied(currentWallpaper, true)
            } else {
                if (previousScheme.length > 0)
                    SettingsStore.setScheme(previousScheme)
                errorMessage = detail || "Palette generation failed"
            }
            pendingScheme = ""
            previousScheme = ""
            operationState = "idle"
            return
        }

        if (kind === "mode") {
            const committed = exitCode === 0 && output.includes("PALETTE=updated")
            if (committed) {
                paletteAvailable = true
                errorMessage = ""
                wallpaperApplied(currentWallpaper, true)
            } else {
                errorMessage = detail || "Theme mode could not be regenerated"
            }
            operationState = "idle"
            return
        }

        if (kind === "themeSource") {
            const committed = exitCode === 0 && output.includes("PALETTE=updated")
            if (committed) {
                if (pendingThemeSourceMode === "color")
                    SettingsStore.setThemeSourceColor(
                        pendingThemeSourceColor, pendingRememberCustom)
                else
                    SettingsStore.setThemeSourceWallpaper()
                pendingThemeSourceMode = ""
                pendingThemeSourceColor = ""
                pendingRememberCustom = false
                paletteAvailable = true
                errorMessage = ""
                wallpaperApplied(currentWallpaper, true)
            } else {
                errorMessage = detail || "Theme source generation failed"
            }
            operationState = "idle"
        }
    }

    property Process discoveryProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = []
                const seen = new Set()
                const thumbDir = Quickshell.env("XDG_CACHE_HOME")
                    || (Quickshell.env("HOME") + "/.cache")
                for (const line of text.split("\n")) {
                    if (!line.trim())
                        continue
                    // `path<TAB>thumb-name` — the shared 500px JPEG thumbnail
                    // generated by `zenith-native wallpaper thumbs`.
                    const sep = line.indexOf("\t")
                    const path = (sep >= 0 ? line.substring(0, sep)
                        : line).trim()
                    if (!path || seen.has(path))
                        continue
                    seen.add(path)
                    const thumbName = sep >= 0
                        ? line.substring(sep + 1).trim() : ""
                    const thumb = thumbName
                        ? root.imageSource(thumbDir + "/zenith/thumbs/"
                            + thumbName) : ""
                    rows.push({
                        path: path,
                        name: root.displayName(path),
                        source: root.imageSource(path),
                        thumb: thumb
                    })
                }
                root.wallpapers = rows
            }
        }
        onExited: exitCode => {
            root.loading = false
            if (exitCode !== 0)
                root.errorMessage = "Wallpaper scan failed"
        }
    }

    property Process operationProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: root.operationOutput = text
        }
        stderr: StdioCollector {
            onStreamFinished: root.operationError = text
        }
        onExited: exitCode => root.finishOperation(exitCode)
    }

    property Timer healthTimer: Timer {
        // Recovery-only polling: while the renderer is ready we trust it —
        // a dead awww daemon surfaces as an error on the next operation and
        // flips state, which re-arms this timer. No steady-state process
        // spawns every 20 seconds.
        interval: 20000
        repeat: true
        running: root.backendState !== "ready" && !root.busy && !root.applying
        onTriggered: root.bootstrap(false)
    }

    property Timer recoveryTimer: Timer {
        interval: 600
        onTriggered: root.bootstrap(true)
    }
}