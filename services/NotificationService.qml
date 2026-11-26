pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import QtCore
import Quickshell.Services.Notifications
import "../core"

Singleton {
    id: root

    readonly property bool serverEnabled: Config.notifications.enabled
    readonly property bool doNotDisturb: Config.notifications.doNotDisturb
    property var history: []
    property var current: null
    property var pendingExactFocus: null
    property var pendingTransientDismiss: null

    // Unread = entries that arrived but have never been seen in the
    // Notification Center. The bell and the dashboard chip light on this,
    // not on the raw history length.
    property int unread: 0
    readonly property int count: history.length
    readonly property bool hasCurrent: current !== null
    readonly property bool currentCritical: current?.critical ?? false

    // History survives shell reloads. Live entries (with a D-Bus source) are
    // serialized without their source/actions; entries restored from disk
    // are passive history only. FileView owns the atomic write below.
    property bool historyLoaded: false

    signal presentationRequested(bool critical)
    signal presentationDismissRequested()
    // Emitted before removal so a transient click can tear down its overlay
    // before the generic current-cleared signal exposes any hover state.
    signal transientDismissRequested()
    signal activationCompleted()
    signal preferencesChanged()

    function plainText(value: string): string {
        return (value || "")
            .replace(/<img\b[^>]*>/gi, "")
            .replace(/<br\s*\/?>/gi, " ")
            .replace(/<[^>]+>/g, "")
            .replace(/&amp;/g, "&")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .trim()
    }

    function receive(notification: Notification): void {
        if (!notification)
            return

        notification.tracked = true
        const entry = {
            id: notification.id,
            source: notification,
            appName: notification.appName || "Application",
            appIcon: notification.appIcon || "",
            desktopEntry: notification.desktopEntry || "",
            image: notification.image || "",
            title: plainText(notification.summary) || "Notification",
            body: plainText(notification.body),
            urgency: notification.urgency,
            critical: notification.urgency === NotificationUrgency.Critical,
            timestamp: Date.now(),
            // Preserve unlabeled `default` actions: many applications use
            // those specifically for clicking the notification body.
            actions: (notification.actions || []).filter(action => !!action),
            provenance: takePendingProvenance(notification.id),
            active: true
        }

        entry.provenance = HyprlandService.identityProvenance(
            entry.desktopEntry, entry.appName)
        history = [entry].concat(history.filter(existing => existing.id !== entry.id))
            .slice(0, Config.notifications.historyLimit)
        unread += 1
        persistHistory()
        notification.closed.connect(reason => markClosed(entry.id, entry.timestamp))

        const shouldPresent = entry.critical
            ? Config.notifications.allowCriticalAlerts
            : Config.notifications.showPopups && !doNotDisturb
        if (shouldPresent) {
            current = entry
            presentationRequested(entry.critical)
        }
    }

    function markAllRead(): void {
        if (unread === 0)
            return
        unread = 0
    }

    function serializeEntry(entry): var {
        // Live D-Bus objects cannot cross a reload; keep plain data only.
        return {
            id: entry.id,
            appName: entry.appName,
            appIcon: entry.appIcon,
            desktopEntry: entry.desktopEntry || "",
            image: entry.image || "",
            title: entry.title,
            body: entry.body,
            urgency: entry.urgency ?? 1,
            critical: !!entry.critical,
            timestamp: entry.timestamp,
            provenance: entry.provenance || null,
            active: !!entry.active
        }
    }

    function persistHistory(): void {
        if (!historyLoaded)
            return
        historyFile.setText(JSON.stringify({
            version: 1,
            unread: unread,
            history: history.slice(0, Config.notifications.historyLimit)
                .map(entry => serializeEntry(entry))
        }))
    }

    function loadHistory(): void {
        let parsed = null
        try {
            parsed = JSON.parse(historyFile.text() || "{}")
        } catch (error) {
            parsed = null
        }
        if (parsed && parsed.version === 1 && Array.isArray(parsed.history)) {
            // Restored entries have no live D-Bus source; clear their action
            // list (actions cannot survive a reload) and drop entries older
            // than two days so stale rows never resurface as popups.
            const cutoff = Date.now() - 2 * 24 * 60 * 60 * 1000
            history = parsed.history.filter(entry => Number(entry.timestamp) >= cutoff)
                .map(entry => Object.assign({}, entry, { source: null, actions: [] }))
            unread = Math.min(Number(parsed.unread || 0), history.filter(
                entry => entry.active).length)
        }
        historyLoaded = true
    }

    function markClosed(id: int, timestamp: double): void {
        history = history.map(entry => {
            if (entry.id !== id || entry.timestamp !== timestamp)
                return entry
            return Object.assign({}, entry, { active: false, source: null, actions: [] })
        })
        persistHistory()
        if (current?.id === id && current?.timestamp === timestamp) {
            current = null
            presentationDismissRequested()
        }
    }

    function dismiss(entry): void {
        if (!entry)
            return
        if (entry.source)
            entry.source.dismiss()
        markClosed(entry.id, entry.timestamp)
    }

    function dismissCurrent(): void {
        dismiss(current)
    }

    function invokePrimaryAction(): void {
        activate(current)
    }

    function visibleActions(entry): var {
        return (entry?.actions || []).filter(action =>
            plainText(action?.text || "").length > 0)
    }

    function queueExactFocus(provenance): void {
        pendingExactFocus = provenance
        exactFocusTimer.restart()
    }

    function canActivate(entry): bool {
        if (!entry)
            return false
        if ((entry.actions || []).some(action => action?.identifier === "default"))
            return true
        return HyprlandService.hasValidExactProvenance(entry.provenance)
    }

    function activate(entry): bool {
        if (!entry)
            return false
        // When we have an exact live origin, release the expanded Island focus
        // grab first, then focus that verified window. A producer default action
        // is retained for entries without exact provenance.
        if (HyprlandService.hasValidExactProvenance(entry.provenance)) {
            requestTransientDismiss(entry)
            activationCompleted()
            queueExactFocus(entry.provenance)
            return true
        }
        const defaultAction = (entry.actions || []).find(action =>
            action?.identifier === "default")
        if (defaultAction) {
            defaultAction.invoke()
            requestTransientDismiss(entry)
            activationCompleted()
            return true
        }
        // Freedesktop metadata identifies an application, not a particular
        // window. Without a live producer action or revalidated provenance,
        // leaving the notification in history is safer than guessing.
        return false
    }

    function invokeAction(entry, index: int): void {
        const actions = visibleActions(entry)
        const action = actions.length > index ? actions[index] : null
        if (action)
            action.invoke()
    }

    function remove(entry): void {
        if (!entry)
            return
        if (entry.active && entry.source)
            entry.source.dismiss()
        history = history.filter(existing => existing.id !== entry.id
            || existing.timestamp !== entry.timestamp)
        persistHistory()
        if (current?.id === entry.id && current?.timestamp === entry.timestamp) {
            current = null
            presentationDismissRequested()
        }
    }

    function dismissTransient(): void {
        requestTransientDismiss(current)
    }

    function requestTransientDismiss(entry): void {
        if (!entry)
            return
        if (current?.id !== entry.id || current?.timestamp !== entry.timestamp) {
            remove(entry)
            return
        }
        if (pendingTransientDismiss)
            return
        pendingTransientDismiss = entry
        transientDismissRequested()
    }

    function completeTransientDismiss(): void {
        const entry = pendingTransientDismiss
        pendingTransientDismiss = null
        if (entry)
            remove(entry)
    }

    function clearHistory(): void {
        for (const entry of history) {
            if (entry.active && entry.source)
                entry.source.dismiss()
        }
        if (current)
            presentationDismissRequested()
        current = null
        history = []
        unread = 0
        persistHistory()
    }

    function toggleDoNotDisturb(): void {
        setDoNotDisturb(!doNotDisturb)
    }

    function setDoNotDisturb(enabled: bool): void {
        SettingsStore.setNotificationToggle("doNotDisturb", enabled)
        preferencesChanged()
        if (enabled && current) {
            current = null
            presentationDismissRequested()
        }
    }

    function setShowPopups(enabled: bool): void {
        SettingsStore.setNotificationToggle("showPopups", enabled)
        preferencesChanged()
        if (!enabled && current && !currentCritical) {
            current = null
            presentationDismissRequested()
        }
    }

    function setAllowCriticalAlerts(enabled: bool): void {
        SettingsStore.setNotificationToggle("allowCriticalAlerts", enabled)
        preferencesChanged()
        if (!enabled && currentCritical) {
            current = null
            presentationDismissRequested()
        }
    }

    function setDuration(key: string, milliseconds: real): void {
        SettingsStore.setNotificationDuration(key, milliseconds)
        preferencesChanged()
    }

    function setHistoryLimit(limit: real): void {
        if (SettingsStore.setNotificationHistoryLimit(limit))
            history = history.slice(0, Math.round(Math.max(20,
                Math.min(100, limit))))
    }

    function resetPreferences(): void {
        SettingsStore.resetNotifications()
        history = history.slice(0, 50)
        preferencesChanged()
    }

    Component.onCompleted: loadHistory()

    property Timer exactFocusTimer: Timer {
        // IslandController releases HyprlandFocusGrab after Animations.fast.
        interval: Animations.fast + 40
        repeat: false
        onTriggered: {
            const provenance = root.pendingExactFocus
            root.pendingExactFocus = null
            if (provenance)
                HyprlandService.focusExactProvenance(provenance)
        }
    }

    property FileView historyFile: FileView {
        path: StandardPaths.writableLocation(
            StandardPaths.GenericStateLocation) + "/zenith/notifications.json"
        watchChanges: false
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: error => console.warn("Zenith notification history:",
            FileViewError.toString(error))
    }

    Instantiator {
        model: root.serverEnabled ? 1 : 0

        delegate: NotificationServer {
            keepOnReload: false
            persistenceSupported: true
            bodySupported: true
            bodyMarkupSupported: false
            bodyHyperlinksSupported: false
            bodyImagesSupported: false
            actionsSupported: true
            actionIconsSupported: false
            imageSupported: false
            inlineReplySupported: false

            onNotification: notification => root.receive(notification)
        }
    }
}
