import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

Item {
    id: root
    signal powerRequested()
    signal captureRequested()
    property bool powerHovered: false
    property bool keepAwakeHovered: false
    // PowerProfile on the left, Clock centered, Weather/KeepAwake on the right.
    // Inactive items (e.g. Weather with no data) are removed entirely instead
    // of hidden, so no phantom gap pushes the cluster off-center.
    function isActive(itemId: string): bool {
        return itemId !== "Weather"
            || (Config.weather.enabled && WeatherService.available)
    }
    readonly property var leftDisplayOrder:
        ["PowerProfile", "Lock"].filter(root.isActive)
    readonly property var rightDisplayOrder:
        ["KeepAwake", "Weather"].filter(root.isActive)
    readonly property real horizontalPadding: Theme.space2
    // Each flank is sized by its own content (not a shared maximum), so the
    // whole cluster is centered and the outer gaps match on both sides.
    readonly property real naturalContentWidth: restClock.implicitWidth
        + leftItems.implicitWidth + rightItems.implicitWidth
        + 2 * Config.island.restItemSpacing
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
                    onKeepAwakeHoveredChanged: if (itemId === "KeepAwake")
                        root.keepAwakeHovered = keepAwakeHovered
                    onLockHoveredChanged: if (itemId === "Lock")
                        root.lockHovered = lockHovered
                    onPowerRequested: root.powerRequested()
                    onCaptureRequested: root.captureRequested()
                    onLockRequested: root.lockRequested()
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
                    onKeepAwakeHoveredChanged: if (itemId === "KeepAwake")
                        root.keepAwakeHovered = keepAwakeHovered
                    onLockHoveredChanged: if (itemId === "Lock")
                        root.lockHovered = lockHovered
                    onPowerRequested: root.powerRequested()
                    onCaptureRequested: root.captureRequested()
                    onLockRequested: root.lockRequested()
                }
            }
        }
    }
}
