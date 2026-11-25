pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// Native presentation bridge for notifications.
//
// Quickshell keeps owning the D-Bus NotificationServer, history, actions and
// DND. This singleton forwards the active popup entries to the Rust engine in
// `zenith-native notify daemon` through the C client, then mirrors the engine's
// atomic JSON snapshot into QML. No notification data is rendered here.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR")
        || "/tmp"
    readonly property string repoRoot: Quickshell.env("ZENITH_ROOT")
        || (Quickshell.shellDir + "/..")
    readonly property string nativeBinary: repoRoot + "/build/zenith-native"
    readonly property string clientBinary: repoRoot + "/build/zenith-notifyctl"
    readonly property string statePath: runtimeDir + "/zenith/notify-state.json"

    property var cards: []
    property bool active: false
    property bool frozen: false
    property int overflow: 0
    property int revision: -1
    readonly property int visibleCount: Math.min(root.cards.length, 3)

    signal cardExpired(int id, real timestamp)

    property var pending: []
    property bool sending: false

    function enqueue(cmd: string, payload: var): void {
        root.pending.push({ cmd: cmd, payload: payload || {} })
        root.flush()
    }

    function flush(): void {
        if (root.sending || root.pending.length === 0)
            return
        const next = root.pending.shift()
        root.sending = true
        commandProcess.command = [root.clientBinary, next.cmd,
            JSON.stringify(next.payload)]
        commandProcess.running = true
    }

    function plain(value: var): string {
        return String(value || "")
            .replace(/<[^>]*>/g, "")
            .replace(/&amp;/g, "&")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .trim()
    }

    // Convert service entries into the engine's wire format. Text is capped
    // because commands travel as a single argv line.
    function sync(entries: var): void {
        const cards = (entries || []).map(entry => {
            const actions = (entry?.actions || []).filter(action =>
                !!action && root.plain(action.text || "").length > 0)
            return {
                id: Number(entry?.id || 0),
                timestamp: Number(entry?.timestamp || 0),
                key: String(entry?.id || 0) + ":" + String(entry?.timestamp || 0),
                app: String(entry?.appName || "Application").slice(0, 200),
                title: String(entry?.title || "Notification").slice(0, 4000),
                body: String(entry?.body || "").slice(0, 4000),
                icon: String(entry?.appIcon || "").slice(0, 512),
                image: String(entry?.image || "").slice(0, 512),
                critical: !!entry?.critical,
                actionLabel: actions.length > 0
                    ? root.plain(actions[0].text).slice(0, 120) : "",
                width: Math.max(320, Config.island.mediaWidth - 24),
                height: Config.notifications.cardHeight,
                gap: Config.notifications.cardGap,
                timeout: entry?.critical
                    ? Config.notifications.criticalTimeout
                    : Config.notifications.timeout
            }
        })
        root.enqueue("sync", { cards: cards })
    }

    function hold(): void { root.enqueue("hold", {}) }
    function release(): void { root.enqueue("release", {}) }
    function clear(): void { root.enqueue("clear", {}) }

    function dismiss(id: int, timestamp: real): void {
        root.enqueue("dismiss", { id: id, timestamp: timestamp })
    }

    function load(raw: string): void {
        let snapshot
        try {
            snapshot = JSON.parse(raw)
        } catch (error) {
            console.warn("Zenith notify bridge: unreadable snapshot")
            return
        }
        const revision = Number(snapshot?.revision || 0)
        if (revision <= root.revision)
            return
        root.revision = revision
        root.cards = snapshot?.cards || []
        root.active = !!snapshot?.active
        root.frozen = !!snapshot?.frozen
        root.overflow = Number(snapshot?.overflow || 0)

        for (const expired of (snapshot?.expired || []))
            root.cardExpired(Number(expired?.id || 0), Number(expired?.timestamp || 0))
    }

    property Process daemon: Process {
        command: [root.nativeBinary, "notify", "daemon"]
        running: true
        onExited: (exitCode, exitStatus) => {
            root.revision = -1
            if (exitCode === 0)
                return
            daemonRestartTimer.restart()
        }
    }

    property Timer daemonRestartTimer: Timer {
        interval: 2000
        repeat: false
        onTriggered: {
            if (!root.daemon.running)
                root.daemon.running = true
        }
    }

    property Process commandProcess: Process {
        running: false
        onExited: (exitCode, exitStatus) => {
            root.sending = false
            Qt.callLater(root.flush)
        }
    }

    property FileView stateFile: FileView {
        path: root.statePath
        watchChanges: true
        blockLoading: true
        preload: true
        printErrors: false
        onLoaded: root.load(text())
        onFileChanged: reload()
        onLoadFailed: {
            root.cards = []
            root.active = false
            root.overflow = 0
            root.revision = -1
        }
    }
}
