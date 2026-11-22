import Quickshell
import QtQuick
import "core"
import "island"
import "services"

ShellRoot {
    Component.onCompleted: {
        ShellState.start()
        WallpaperService.refresh()
        WallpaperService.bootstrap(false)
    }

    Variants {
        model: Quickshell.screens

        IslandHost {
            required property var modelData
            screen: modelData
        }
    }
}
