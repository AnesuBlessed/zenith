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
    // Stored on the root (not aliased) so Island can write it even while
    // the settings page is unloaded; the page binds to it on creation.
    property string settingsSection: ""
    readonly property bool overviewOpen: page === "overview"
    readonly property bool notificationsOpen: page === "notifications"
    readonly property bool captureOpen: page === "capture"
    readonly property bool sessionOpen: page === "session"
    readonly property bool settingsOpen: page === "settings"
    readonly property bool settingsLivePreviewActive: active && settingsOpen
        && (settingsLoader.item ? settingsLoader.item.livePreviewActive : false)
    readonly property string settingsPreviewMode:
        settingsLoader.item ? settingsLoader.item.pillPreviewMode : ""
    readonly property bool controlCenterOpen: page === "control-center"
    readonly property bool clipboardOpen: page === "clipboard"
    readonly property bool identityPickerOpen: page === "identity-image"
    property string identityReturnPage: "overview"
    readonly property bool insightOpen: page === "weather" || page === "calendar"
        || page === "media-center" || page === "system" || page === "battery"
    readonly property bool controlCenterDetailOpen:
        controlCenterOpen && controlCenterLoader.item
            && controlCenterLoader.item.detailOpen
    readonly property real controlCenterDetailProgress:
        (controlCenterOpen && controlCenterLoader.item)
            ? controlCenterLoader.item.detailProgress : 0
    readonly property bool controlCenterDetailTransitionActive:
        (controlCenterOpen && controlCenterLoader.item)
            && controlCenterLoader.item.detailTransitionActive
    signal pageSelected(string selectedPage)
    signal dismissRequested(bool forceDormant)

    // Wake the SystemService metrics timers only while a page that shows
    // them (overview / insights) is actually on screen.
    Component.onCompleted: SystemService.consumerVisible = Qt.binding(
        () => root.overviewOpen || root.insightOpen)

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
        const session = sessionLoader.item
        if (sessionOpen && session && session.cancelConfirmation())
            return true
        const control = controlCenterLoader.item
        if (controlCenterOpen && control && control.closeExpandedSection())
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
                        text: NotificationService.unread > 0 ? "󰂚" : "󰂜"
                        color: NotificationService.unread > 0 ? Theme.primary
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
                        text: "󰄨"
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

        // Every page below is lazy: the Loader only builds the component
        // tree while its page is open. Idle RAM and startup time drop by
        // the combined weight of the unloaded pages; the cost is one frame
        // of build time on a page's first open. The overview Dashboard is
        // the resting page, so it still loads immediately.

        Loader {
            asynchronous: true
            active: root.notificationsOpen
            visible: active
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: NotificationCenter {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        Loader {
            asynchronous: true
            active: root.captureOpen
            visible: active
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: CapturePage {
                monitor: root.monitor
                Layout.fillWidth: true
                Layout.fillHeight: true
                onDismissRequested: forceDormant =>
                    root.dismissRequested(forceDormant)
            }
        }

        Loader {
            asynchronous: true
            id: sessionLoader
            active: root.sessionOpen
            visible: active
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: SessionPage {
                Layout.fillWidth: true
                Layout.fillHeight: true
                onDismissRequested: root.dismissRequested(false)
            }
        }

        Loader {
            asynchronous: true
            id: settingsLoader
            active: root.settingsOpen
            visible: active
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: SettingsPage {
                section: root.settingsSection
                onSectionChanged: root.settingsSection = section
                monitor: root.monitor
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        Loader {
            asynchronous: true
            active: root.overviewOpen
            visible: active
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: Dashboard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                onPageRequested: page => root.pageSelected(page)
            }
        }

        Loader {
            asynchronous: true
            id: controlCenterLoader
            active: root.controlCenterOpen
            visible: active
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: ControlCenter {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        Loader {
            asynchronous: true
            active: root.insightOpen
            visible: active
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: InsightCenter {
                selectedPage: root.page
                Layout.fillWidth: true
                Layout.fillHeight: true
                onPageRequested: page => root.pageSelected(page)
            }
        }

        Loader {
            asynchronous: true
            active: root.identityPickerOpen
            visible: active
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: WallpaperPage {
                monitor: root.monitor
                selectionMode: true
                Layout.fillWidth: true
                Layout.fillHeight: true
                onSelectionCompleted: root.closeIdentityPicker()
                onCancelRequested: root.closeIdentityPicker()
            }
        }

        Loader {
            asynchronous: true
            active: root.clipboardOpen
            visible: active
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: ClipboardPage {
                Layout.fillWidth: true
                Layout.fillHeight: true
                onCloseRequested: root.pageSelected("overview")
            }
        }
    }
}
