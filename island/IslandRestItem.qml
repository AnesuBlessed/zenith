import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

Item {
    id: root
    required property string itemId
    property bool powerHovered: false
    property bool keepAwakeHovered: false
    property bool lockHovered: false
    signal powerRequested()
    signal captureRequested()
    signal lockRequested()
    implicitWidth: contentLoader.item?.implicitWidth ?? 0
    implicitHeight: 20

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.itemId === "Weather" ? weatherComponent
            : root.itemId === "Clock" ? clockComponent
            : root.itemId === "KeepAwake" ? keepAwakeComponent
            : root.itemId === "PowerProfile" ? powerComponent
            : root.itemId === "Lock" ? lockComponent : null
    }

    Component {
        id: weatherComponent
        Item {
            // Collapse to zero width when inactive so the resting row stays
            // centered even while the slot exists.
            property bool active: Config.weather.enabled && WeatherService.available
            visible: active
            implicitWidth: active ? Math.round(14 * Config.island.restIconScale) : 0
            implicitHeight: 20
            Text {
                anchors.centerIn: parent
                text: WeatherService.icon
                color: Theme.tertiary
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Math.round(12 * Config.island.restIconScale)
            }
        }
    }


    Component {
        id: clockComponent
        Text {
            text: ShellState.time
            color: Theme.surfaceText
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: Math.round(11 * Config.island.restTextScale)
            font.weight: Font.Bold
        }
    }

    Component {
        id: keepAwakeComponent
        Item {
            implicitWidth: Math.round(14 * Config.island.restIconScale)
            implicitHeight: 20
            Text {
                anchors.centerIn: parent
                text: "󰅶"
                color: IdleService.inhibited ? Theme.error : Theme.surfaceText
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Math.round(11 * Config.island.restIconScale)
            }
            HoverHandler {
                onHoveredChanged: root.keepAwakeHovered = hovered
            }
            TapHandler { onTapped: IdleService.toggleInhibition() }
        }
    }

    Component {
        id: powerComponent
        Item {
            implicitWidth: 18
            implicitHeight: 20
            Text {
                visible: !CaptureService.recording
                anchors.centerIn: parent
                text: PowerProfileService.icon
                color: PowerProfileService.profileName === "Performance" ? Theme.warning
                    : PowerProfileService.profileName === "Power saver" ? Theme.success
                    : Theme.surfaceVariantText
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Math.round(11 * Config.island.restIconScale)
            }
            RecordingDot {
                anchors.centerIn: parent
                visible: CaptureService.recording
                active: visible
                dotSize: Math.round(8 * Config.island.restIconScale)
            }
            HoverHandler { onHoveredChanged: root.powerHovered = hovered }
            TapHandler {
                onTapped: CaptureService.recording
                    ? root.captureRequested() : root.powerRequested()
            }
        }
    }

    Component {
        id: lockComponent
        Item {
            implicitWidth: 18
            implicitHeight: 20
            Text {
                anchors.centerIn: parent
                text: "󰌾"
                color: Theme.surfaceVariantText
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Math.round(11 * Config.island.restIconScale)
            }
            HoverHandler { onHoveredChanged: root.lockHovered = hovered }
            TapHandler { onTapped: root.lockRequested() }
        }
    }
}
