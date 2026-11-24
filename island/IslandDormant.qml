import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

Item {
    id: root
    signal powerRequested()
    signal captureRequested()
    property bool powerHovered: false
    // Force PowerProfile to be first, followed by Dnd on the left, Clock centered, Weather/KeepAwake on the right
    readonly property var displayOrder: ["PowerProfile", "Dnd", "KeepAwake", "Weather"]
    readonly property var leftDisplayOrder: ["PowerProfile", "Dnd"]
    readonly property var rightDisplayOrder: ["KeepAwake", "Weather"]
    readonly property real horizontalPadding: Theme.space2
    readonly property real sideWidth: Math.max(
        leftItems.implicitWidth, rightItems.implicitWidth, 48)
    readonly property real naturalContentWidth: restClock.implicitWidth
        + 2 * (sideWidth + Config.island.restItemSpacing)
    readonly property real availableContentWidth: Math.max(0,
        width - horizontalPadding * 2)
    readonly property real fitScale: naturalContentWidth > 0
        ? Math.min(1, availableContentWidth / naturalContentWidth) : 1

    Item {
        id: fittedContent
        anchors.centerIn: parent
        width: root.naturalContentWidth
        height: parent.height
        scale: root.fitScale

        RowLayout {
            id: leftItems
            anchors.right: restClock.left
            anchors.rightMargin: Config.island.restItemSpacing
            anchors.verticalCenter: parent.verticalCenter
            width: root.sideWidth
            Layout.alignment: Qt.AlignRight
            spacing: Config.island.restItemSpacing

            Repeater {
                model: root.leftDisplayOrder
                delegate: IslandRestItem {
                    required property string modelData
                    itemId: modelData
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                    onPowerHoveredChanged: if (itemId === "PowerProfile")
                        root.powerHovered = powerHovered
                    onPowerRequested: root.powerRequested()
                    onCaptureRequested: root.captureRequested()
                }
            }
        }

        IslandRestItem {
            id: restClock
            anchors.centerIn: parent
            itemId: "Clock"
        }

        RowLayout {
            id: rightItems
            anchors.left: restClock.right
            anchors.leftMargin: Config.island.restItemSpacing
            anchors.verticalCenter: parent.verticalCenter
            width: root.sideWidth
            Layout.alignment: Qt.AlignLeft
            spacing: Config.island.restItemSpacing

            Repeater {
                model: root.rightDisplayOrder
                delegate: IslandRestItem {
                    required property string modelData
                    itemId: modelData
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                    onPowerHoveredChanged: if (itemId === "PowerProfile")
                        root.powerHovered = powerHovered
                    onPowerRequested: root.powerRequested()
                    onCaptureRequested: root.captureRequested()
                }
            }
        }
    }
}
