import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

Item {
    id: root

    signal closeRequested()

    property string query: ""
    readonly property var filteredEntries: {
        const needle = root.query.trim().toLowerCase()
        if (needle.length === 0)
            return ClipboardService.entries
        return ClipboardService.entries.filter(entry =>
            (entry.search || "").toLowerCase().includes(needle))
    }

    onVisibleChanged: {
        if (visible) {
            ClipboardService.refresh()
            ClipboardService.beginPresentation()
        } else {
            ClipboardService.endPresentation()
        }
    }

    Connections {
        target: ClipboardService
        function onCopied(): void { root.closeRequested() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space2

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            spacing: Theme.space2

            ColumnLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: 190
                spacing: 0
                Text {
                    text: "Clipboard"
                    color: Theme.surfaceText
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Config.island.expandedPixelSize(Theme.textTitle, false)
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: ClipboardService.errorMessage.length > 0
                        ? ClipboardService.errorMessage
                        : ClipboardService.entries.length + " recent entries"
                    color: ClipboardService.errorMessage.length > 0
                        ? Theme.warning : Theme.surfaceVariantText
                    elide: Text.ElideRight
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Config.island.expandedPixelSize(9, false)
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 34
                radius: Theme.radiusMedium
                color: Qt.alpha(Theme.surfaceContainerHigh, 0.62)
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space3
                    anchors.rightMargin: Theme.space3
                    spacing: Theme.space2
                    Text {
                        text: "󰍉"
                        color: Theme.surfaceVariantText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Config.island.expandedPixelSize(13, true)
                    }
                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        color: Theme.surfaceText
                        selectionColor: Theme.primaryContainer
                        selectedTextColor: Theme.primaryContainerText
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Config.island.expandedPixelSize(11, false)
                        clip: true
                        onTextChanged: root.query = text
                        Text {
                            visible: searchInput.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search clipboard"
                            color: Theme.surfaceVariantText
                            font: searchInput.font
                        }
                    }
                }
            }

            TextButton {
                Layout.preferredHeight: 34
                compact: true
                text: "󰃢"
                labelFontFamily: Config.appearance.monoFontFamily
                // Wipes the whole history immediately — no confirmation step.
                enabled: ClipboardService.entries.length > 0
                onClicked: ClipboardService.clearHistory()
            }
            TextButton {
                Layout.preferredHeight: 34
                text: "Close"
                onClicked: root.closeRequested()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Qt.alpha(Theme.surfaceContainerLow, 0.48)
            border.width: Config.island.expandedItemBordersEnabled ? 1 : 0
            border.color: Qt.alpha(Theme.outlineVariant, 0.32)
            clip: true

            ListView {
                id: history
                anchors.fill: parent
                anchors.margins: Theme.space2
                clip: true
                spacing: 4
                model: root.filteredEntries
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    required property var modelData
                    width: history.width
                    height: 52
                    radius: Theme.radiusMedium
                    color: hover.containsMouse
                        ? Qt.alpha(Theme.surfaceContainerHigh, 0.8)
                        : Qt.alpha(Theme.surfaceContainerLow, 0.5)
                    border.width: Config.island.expandedItemBordersEnabled ? 1 : 0
                    border.color: Qt.alpha(Theme.outlineVariant, 0.3)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space2
                        anchors.rightMargin: Theme.space2
                        spacing: Theme.space2

                        Rectangle {
                            visible: modelData.kind === "image"
                            Layout.preferredWidth: 58
                            Layout.preferredHeight: 38
                            radius: Theme.radiusSmall
                            color: Qt.alpha(Theme.surfaceContainerHigh, 0.7)
                            clip: true

                            Image {
                                anchors.fill: parent
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                source: ClipboardService.thumbnailSource(modelData.id)
                            }
                            Component.onCompleted: ClipboardService.requestPreview(modelData)
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.preview
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            font.family: Config.appearance.fontFamily
                            font.pixelSize: Config.island.expandedPixelSize(10, false)
                        }

                        Text {
                            text: "󰆴"
                            color: deleteArea.containsMouse
                                ? Theme.error : Theme.surfaceVariantText
                            font.family: Config.appearance.monoFontFamily
                            font.pixelSize: Config.island.expandedPixelSize(13, true)

                            MouseArea {
                                id: deleteArea
                                z: 2
                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ClipboardService.remove(modelData.id)
                            }
                        }
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton
                        onClicked: ClipboardService.copy(modelData.id)
                    }
                }
            }

            ColumnLayout {
                visible: !ClipboardService.loading && root.filteredEntries.length === 0
                anchors.centerIn: parent
                spacing: Theme.space2
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰅍"
                    color: Theme.surfaceVariantText
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: Config.island.expandedPixelSize(28, true)
                }
                Text {
                    text: root.query.length > 0
                        ? "No matching entries" : "Nothing copied yet"
                    color: Theme.surfaceVariantText
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Config.island.expandedPixelSize(Theme.textBody, false)
                }
            }
        }
    }
}