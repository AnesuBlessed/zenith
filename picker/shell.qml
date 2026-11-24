import Quickshell
import Quickshell.Io
import QtQuick

// Zenith wallpaper picker entry point.
//
// The picker is a standalone Quickshell configuration launched by
// `zenith-ctl toggle picker`. It reuses the hyprquickpaper layouts (ported to
// the Zenith palette) and shares the shell's native backend, so applying a
// wallpaper from here updates the whole desktop exactly like the in-shell
// wallpaper page.
Scope {
    id: root

    property string activeLayout: "shell-floating.qml"

    FileView {
        id: configFile
        path: Quickshell.shellPath("config.json")
        watchChanges: true
        blockLoading: true
        preload: true
        onLoaded: root.readConfig(text())
        onFileChanged: reload()
    }

    function readConfig(raw: string): void {
        try {
            const parsed = JSON.parse(raw)
            if (parsed.active_layout)
                root.activeLayout = parsed.active_layout
        } catch (error) {
            console.warn("Zenith picker: config unreadable:", error)
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Loader {
            id: layoutLoader
            required property var modelData
            active: true
            asynchronous: false
            // Bound, not set-once: rewriting config.json's active_layout
            // (Settings → Wallpaper → Picker layout, or by hand) swaps the
            // layout live on every monitor.
            source: "layouts/" + root.activeLayout

            onStatusChanged: {
                if (status === Loader.Error)
                    console.warn("Zenith picker: layout failed to load:",
                        root.activeLayout)
            }

            onLoaded: {
                if (item && item.screen !== undefined)
                    item.screen = modelData
            }
        }
    }
}