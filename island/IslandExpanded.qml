import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../panels"
import "../services"

Item {
    id: root

    property var monitor
    property string page: "overview"
    property bool active: false
    property alias settingsSection: settingsPage.section
    readonly property bool overviewOpen: page === "overview"
    readonly property bool notificationsOpen: page === "notifications"
    readonly property bool captureOpen: page === "capture"
    readonly property bool sessionOpen: page === "session"
    readonly property bool settingsOpen: page === "settings"
    readonly property bool settingsLivePreviewActive: active && settingsOpen
        && settingsPage.livePreviewActive
    readonly property string settingsPreviewMode: settingsPage.pillPreviewMode
    readonly property bool controlCenterOpen: page === "control-center"
    readonly property bool clipboardOpen: page === "clipboard"
    readonly property bool identityPickerOpen: page === "identity-image"
    property string identityReturnPage: "overview"
    readonly property bool insightOpen: page === "weather" || page === "calendar"
        || page === "media-center" || page === "system" || page === "battery"
    readonly property bool controlCenterDetailOpen:
        controlCenterOpen && controlCenter.detailOpen
    readonly property real controlCenterDetailProgress:
        controlCenterOpen ? controlCenter.detailProgress : 0
    readonly property bool controlCenterDetailTransitionActive:
        controlCenterOpen && controlCenter.detailTransitionActive
    signal pageSelected(string selectedPage)
    signal dismissRequested(bool forceDormant)

    function openIdentityPicker(): void {
        if (identityPickerOpen) {
            pageSelected(identityReturnPage)
            return
        }
        identityReturnPage = page
        pageSelected("identity-image")
    }

    function closeIdentityPicker(): void {
        if (!identityPickerOpen)
            return
        pageSelected(identityReturnPage)
    }

    function closeTransientUi(): bool {
        if (identityPickerOpen) {
            closeIdentityPicker()
            return true
        }
        if (sessionOpen && sessionPage.cancelConfirmation())
            return true
        if (controlCenterOpen && controlCenter.closeExpandedSection())
            return true
        return false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space3
        spacing: Theme.space3

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 34

            RowLayout {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.space2
                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 30
                    radius: Theme.radiusSmall
                    color: root.sessionOpen ? Theme.primaryContainer
                        : sessionNavHover.hovered
                            ? Theme.surfaceContainerHigh : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰐥"
                        color: root.sessionOpen
                            ? Theme.primaryContainerText : Theme.surfaceVariantText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Config.island.expandedTopIconPixelSize(Theme.iconSmall)
                    }

                    HoverHandler { id: sessionNavHover }
                    TapHandler {
                        onTapped: root.pageSelected(root.sessionOpen
                            ? "overview" : "session")
                    }

                    Behavior on color { ColorAnimation { duration: Animations.fast } }
                }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 30
                    radius: Theme.radiusSmall
                    color: root.captureOpen ? Theme.primaryContainer
                        : captureNavHover.hovered
                            ? Theme.surfaceContainerHigh : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: CaptureService.recording ? "󰑊" : "󰄀"
                        color: CaptureService.recording ? Theme.error
                            : root.captureOpen ? Theme.primaryContainerText
                            : Theme.surfaceVariantText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Config.island.expandedTopIconPixelSize(Theme.iconSmall)
                    }

                    HoverHandler { id: captureNavHover }
                    TapHandler {
                        onTapped: root.pageSelected(root.captureOpen
                            ? "overview" : "capture")
                    }

                    Behavior on color { ColorAnimation { duration: Animations.fast } }
                }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 30
                    radius: Theme.radiusSmall
                    color: root.notificationsOpen ? Theme.primaryContainer
                        : notificationsNavHover.hovered
                            ? Theme.surfaceContainerHigh : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: NotificationService.count > 0 ? "󰂚" : "󰂜"
                        color: NotificationService.count > 0 ? Theme.primary
                            : root.notificationsOpen ? Theme.primaryContainerText
                            : Theme.surfaceVariantText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Config.island.expandedTopIconPixelSize(Theme.iconSmall)
                    }

                    HoverHandler { id: notificationsNavHover }
                    TapHandler {
                        onTapped: root.pageSelected(root.notificationsOpen
                            ? "overview" : "notifications")
                    }

                    Behavior on color { ColorAnimation { duration: Animations.fast } }
                }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 30
                    radius: Theme.radiusSmall
                    color: root.controlCenterOpen ? Theme.primaryContainer
                        : controlsNavHover.hovered
                            ? Theme.surfaceContainerHigh : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰘮"
                        color: root.controlCenterOpen
                            ? Theme.primaryContainerText : Theme.surfaceVariantText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Config.island.expandedTopIconPixelSize(Theme.iconSmall)
                    }

                    HoverHandler { id: controlsNavHover }
                    TapHandler {
                        onTapped: root.pageSelected(root.controlCenterOpen
                            ? "overview" : "control-center")
                    }

                    Behavior on color { ColorAnimation { duration: Animations.fast } }
                }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 30
                    radius: Theme.radiusSmall
                    color: root.overviewOpen ? Theme.primaryContainer
                        : overviewNavHover.hovered
                            ? Theme.surfaceContainerHigh : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰕮"
                        color: root.overviewOpen
                            ? Theme.primaryContainerText : Theme.surfaceVariantText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Config.island.expandedTopIconPixelSize(Theme.iconSmall)
                    }

                    HoverHandler { id: overviewNavHover }
                    TapHandler {
                        onTapped: root.pageSelected("overview")
                    }

                    Behavior on color { ColorAnimation { duration: Animations.fast } }
                }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 30
                    radius: Theme.radiusSmall
                    color: root.insightOpen ? Theme.primaryContainer
                        : insightsNavHover.hovered
                            ? Theme.surfaceContainerHigh : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰕮"
                        color: root.insightOpen
                            ? Theme.primaryContainerText : Theme.surfaceVariantText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Config.island.expandedTopIconPixelSize(Theme.iconSmall)
                    }

                    HoverHandler { id: insightsNavHover }
                    TapHandler {
                        onTapped: root.pageSelected(root.insightOpen ? "overview" : "weather")
                    }

                    Behavior on color { ColorAnimation { duration: Animations.fast } }
                }

                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 30
                    radius: Theme.radiusSmall
                    color: root.settingsOpen ? Theme.primaryContainer
                        : settingsNavHover.hovered
                            ? Theme.surfaceContainerHigh : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "󰒓"
                        color: root.settingsOpen
                            ? Theme.primaryContainerText : Theme.surfaceVariantText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Config.island.expandedTopIconPixelSize(Theme.iconSmall)
                    }

                    HoverHandler { id: settingsNavHover }
                    TapHandler {
                        onTapped: root.pageSelected(root.settingsOpen
                            ? "overview" : "settings")
                    }

                    Behavior on color { ColorAnimation { duration: Animations.fast } }
                }


            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: ShellState.time
                color: Theme.primary
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Config.island.expandedPixelSize(Theme.textBody, false)
                font.weight: Font.Bold
            }
        }

        NotificationCenter {
            visible: root.notificationsOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        CapturePage {
            visible: root.captureOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            monitor: root.monitor
            onDismissRequested: forceDormant =>
                root.dismissRequested(forceDormant)
        }

        SessionPage {
            id: sessionPage
            visible: root.sessionOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            onDismissRequested: root.dismissRequested(false)
        }

        SettingsPage {
            id: settingsPage
            visible: root.settingsOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            monitor: root.monitor
        }

        Dashboard {
            visible: root.overviewOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            onPageRequested: page => root.pageSelected(page)
        }

        ControlCenter {
            id: controlCenter
            visible: root.controlCenterOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        InsightCenter {
            visible: root.insightOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            selectedPage: root.page
            onPageRequested: page => root.pageSelected(page)
        }

        WallpaperPage {
            visible: root.identityPickerOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            monitor: root.monitor
            selectionMode: root.identityPickerOpen
            onSelectionCompleted: root.closeIdentityPicker()
            onCancelRequested: root.closeIdentityPicker()
        }
        ClipboardPage {
            visible: root.clipboardOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            onCloseRequested: root.pageSelected("overview")
        }
    }
}
