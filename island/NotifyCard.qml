import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../services"

// One native-driven notification card. The engine owns motion; this component
// owns only the Quickshell-side rendering and click behaviour.
Item {
    id: root
    required property var modelData

    readonly property var entry: {
        const id = Number(root.modelData?.id || 0)
        const timestamp = Number(root.modelData?.timestamp || 0)
        const history = NotificationService.history || []
        return history.find(candidate => candidate.id === id
            && candidate.timestamp === timestamp) || null
    }
    readonly property color accent: root.modelData?.critical
        ? Theme.error : Theme.primary
    readonly property string iconSource: {
        if (root.modelData?.image)
            return root.modelData.image
        if (root.modelData?.icon)
            return Quickshell.iconPath(root.modelData.icon, true)
        return ""
    }

    x: Number(root.modelData?.x ?? 0)
    y: Number(root.modelData?.y ?? 0)
    z: 100 - Number(root.modelData?.depth || 0)
    width: Number(root.modelData?.width ?? parent.width)
    height: Number(root.modelData?.height ?? 74)
    opacity: Number(root.modelData?.opacity ?? 1)
    scale: Number(root.modelData?.scale ?? 1)
    transformOrigin: Item.TopCenter

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: Qt.alpha(Theme.surfaceContainerHigh, 0.97)
        border.width: 1
        border.color: Qt.alpha(root.accent, root.modelData?.critical ? 0.55 : 0.26)

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.space3
            spacing: Theme.space3

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: Theme.radiusSmall
                color: Qt.alpha(root.accent, Theme.dark ? 0.18 : 0.12)
                border.width: 1
                border.color: Qt.alpha(root.accent, 0.30)
                clip: true

                Image {
                    id: cardIcon
                    anchors.fill: parent
                    anchors.margins: Theme.space2
                    source: root.iconSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.iconSource.length === 0
                        || cardIcon.status === Image.Error
                    text: root.modelData?.critical ? "󰀦" : "󰂚"
                    color: root.accent
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: Theme.iconMedium
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2

                    Text {
                        Layout.fillWidth: true
                        text: root.modelData?.app || "Application"
                        color: root.accent
                        elide: Text.ElideRight
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    Text {
                        visible: !!root.modelData?.critical
                        text: "CRITICAL"
                        color: Theme.error
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: root.modelData?.title || "Notification"
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.textBody
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.modelData?.body || ""
                    color: Theme.surfaceVariantText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.textSmall
                }
            }

            // Drip-style action row: every labeled action the app sent is a
            // real button, not just the first one.
            Row {
                visible: (root.modelData?.actionLabels || []).length > 0
                spacing: Theme.space1

                Repeater {
                    model: (root.modelData?.actionLabels || []).slice(0, 2)

                    delegate: Rectangle {
                        required property string modelData
                        readonly property int actionIndex:
                            (root.modelData?.actionLabels || []).indexOf(modelData)
                        Layout.alignment: Qt.AlignVCenter
                        width: actionText.implicitWidth + Theme.space3
                        height: 30
                        radius: Theme.radiusSmall
                        color: actionPointer.hovered ? Theme.primaryContainer
                            : Theme.surfaceContainer

                        Text {
                            id: actionText
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: actionPointer.hovered
                                ? Theme.primaryContainerText : Theme.surfaceText
                            font.family: Config.appearance.fontFamily
                            font.pixelSize: Theme.textSmall
                            font.weight: Font.Medium
                        }

                        HoverHandler { id: actionPointer }
                        TapHandler {
                            onTapped: {
                                if (root.entry)
                                    NotificationService.invokeAction(root.entry,
                                        parent.actionIndex)
                            }
                        }
                    }
                }
            }

            Text {
                Layout.preferredWidth: 18
                text: "×"
                color: closePointer.hovered ? Theme.error : Theme.outline
                font.pixelSize: 18
                horizontalAlignment: Text.AlignHCenter

                HoverHandler { id: closePointer }
                TapHandler {
                    onTapped: {
                        if (root.entry)
                            NotificationService.dismiss(root.entry)
                    }
                }
            }
        }
    }

    TapHandler {
        onTapped: {
            if (!root.entry)
                return
            if (!NotificationService.activate(root.entry))
                NotificationService.dismiss(root.entry)
        }
    }
}
