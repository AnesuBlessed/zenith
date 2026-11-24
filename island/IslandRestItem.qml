import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

Item {
    id: root
    required property string itemId
    property bool powerHovered: false
    signal powerRequested()
    signal captureRequested()
    implicitWidth: contentLoader.item?.implicitWidth ?? 0
    implicitHeight: 20

    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: root.itemId === "Weather" ? weatherComponent
            : root.itemId === "Dnd" ? dndComponent
            : root.itemId === "Clock" ? clockComponent
            : root.itemId === "KeepAwake" ? keepAwakeComponent
            : root.itemId === "PowerProfile" ? powerComponent : null
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
        id: dndComponent
        Item {
            implicitWidth: NotificationService.count > 0 ? 24 : Math.round(14 * Config.island.restIconScale)
            implicitHeight: 20
            Behavior on implicitWidth { NumberAnimation { duration: Animations.fast } }

            Text {
                visible: NotificationService.count === 0
                anchors.centerIn: parent
                // Crescent moon icon for Do Not Disturb
                text: NotificationService.doNotDisturb ? "󰃜" : "󰂚"
                color: NotificationService.doNotDisturb
                    ? Theme.tertiary : Theme.surfaceText
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Math.round(11 * Config.island.restIconScale)
            }
            Rectangle {
                visible: NotificationService.count > 0
                anchors.centerIn: parent
                width: Math.max(16, notifyCountText.implicitWidth + 8)
                height: 15
                radius: height / 2
                color: Theme.error
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 2
                    Text {
                        text: "󰂚"
                        color: "#ffffff"
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 8
                    }
                    Text {
                        id: notifyCountText
                        text: NotificationService.count > 99 ? "99+" : NotificationService.count
                        color: "#ffffff"
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Math.round(8 * Config.island.restTextScale)
                        font.weight: Font.Bold
                    }
                }
            }
            TapHandler { onTapped: NotificationService.toggleDoNotDisturb() }
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
}
