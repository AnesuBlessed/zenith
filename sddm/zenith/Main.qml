// =============================================================================
//  ZENITH — SDDM GREETER
//  Visually mirrors the hyprlock lock screen: current wallpaper background,
//  right-hand content column in Zenith Display, minimal pills. Keeps all the
//  options a stock install has: user, password, session selection, power.
// =============================================================================

import QtQuick

Rectangle {
    id: root

    color: "#0a0c12"

    // Current wallpaper (pre-blurred + dimmed, mirrored by the native engine)
    Image {
        anchors.fill: parent
        source: "file:///var/lib/zenith/lock-bg.png"
        fillMode: Image.PreserveAspectCrop
    }

    // Soft dim so light wallpapers keep the text legible
    Rectangle {
        anchors.fill: parent
        color: "#060810"
        opacity: 0.18
    }

    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    // ------------------------------------------------------------------
    //  Session state
    // ------------------------------------------------------------------
    property var sessionNames: []
    function registerSession(name, comment) {
        if (name)
            sessionNames.push({ name: name, comment: comment || "" })
    }
    Component.onCompleted: {
        // Start on the last-used session (fall back to the first)
        for (let j = 0; j < sessionNames.length; j++) {
            if (sessionNames[j].name === sddm.lastSession) {
                sessionIndex = j
                break
            }
        }
        usernameInput.text = sddm.lastUser || ""
        passwordInput.forceActiveFocus()
    }

    // Delegates register themselves as the greeter model materializes
    // (SDDM models are plain QAbstractListModel — no .get() from QML).
    Repeater {
        model: sessionModel
        delegate: Item {
            readonly property string sName: model.name || ""
            readonly property string sComment: model.comment || ""
            Component.onCompleted: root.registerSession(sName, sComment)
        }
    }

    property int sessionIndex: 0
    property string currentSession: sessionNames.length
        ? sessionNames[Math.min(sessionIndex, sessionNames.length - 1)].name : ""
    property string currentSessionLabel: {
        const s = sessionNames.length
            ? sessionNames[Math.min(sessionIndex, sessionNames.length - 1)] : null
        if (!s) return "no sessions"
        const base = s.name.split(" ").pop()
        return base.charAt(0).toUpperCase() + base.slice(1)
    }

    function cycleSession() {
        if (sessionNames.length)
            sessionIndex = (sessionIndex + 1) % sessionNames.length
    }

    function attemptLogin() {
        if (passwordInput.text === "") {
            passwordInput.forceActiveFocus()
            return
        }
        loginError = ""
        sddm.login(usernameInput.text, passwordInput.text, currentSession)
        passwordInput.text = ""
    }

    property string loginError: ""
    Connections {
        target: sddm
        function onLoginFailed() {
            root.loginError = "wrong password"
        }
    }

    // ------------------------------------------------------------------
    //  Right content column (72% of the screen, mirrors hyprlock)
    // ------------------------------------------------------------------
    Item {
        id: column
        x: parent.width * 0.72
        width: Math.min(parent.width * 0.26, 360)
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -24

        Column {
            width: parent.width
            spacing: 10

            Item {
                width: parent.width
                height: 120

                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    text: Qt.formatTime(root.now, "HH:mm")
                    color: "#e4ebf5"
                    font.family: "Zenith Display"
                    font.pixelSize: 104
                }
                Text {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 8
                    text: root.now.getHours() < 12 ? "AM" : "PM"
                    color: "#9aa7b8"
                    font.family: "Zenith Display"
                    font.pixelSize: 20
                }
            }

            Text {
                anchors.left: parent.left
                text: Qt.formatDate(root.now, "dddd, MMMM d")
                color: "#9aa7b8"
                font.family: "Zenith Display"
                font.pixelSize: 20
            }

            Item { width: 1; height: 8 }

            // Username pill
            Rectangle {
                width: parent.width
                height: 44
                radius: 22
                color: Qt.rgba(0.08, 0.10, 0.15, 0.75)
                border.width: 1
                border.color: Qt.rgba(0.55, 0.75, 0.92, 0.35)

                TextInput {
                    id: usernameInput
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    verticalAlignment: TextInput.AlignVCenter
                    color: "#e4ebf5"
                    font.family: "Zenith Display"
                    font.pixelSize: 15
                    clip: true
                    selectByMouse: true
                    KeyNavigation.tab: passwordInput
                    Keys.onReturnPressed: root.attemptLogin()
                    Keys.onEnterPressed: root.attemptLogin()

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Username"
                        color: Qt.rgba(0.72, 0.78, 0.86, 0.6)
                        font.family: "Zenith Display"
                        font.pixelSize: 15
                        visible: usernameInput.text.length === 0
                    }
                }
            }

            // Password pill
            Rectangle {
                width: parent.width
                height: 44
                radius: 22
                color: Qt.rgba(0.08, 0.10, 0.15, 0.75)
                border.width: 1
                border.color: root.loginError !== ""
                    ? Qt.rgba(0.94, 0.35, 0.35, 0.7)
                    : Qt.rgba(0.55, 0.75, 0.92, 0.35)

                TextInput {
                    id: passwordInput
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    verticalAlignment: TextInput.AlignVCenter
                    color: "#e4ebf5"
                    font.family: "Zenith Display"
                    font.pixelSize: 15
                    clip: true
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    Keys.onReturnPressed: root.attemptLogin()
                    Keys.onEnterPressed: root.attemptLogin()

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Password"
                        color: Qt.rgba(0.72, 0.78, 0.86, 0.6)
                        font.family: "Zenith Display"
                        font.pixelSize: 15
                        visible: passwordInput.text.length === 0
                    }
                }
            }

            Text {
                visible: root.loginError !== ""
                text: root.loginError
                color: "#f05a5a"
                font.family: "Zenith Display"
                font.pixelSize: 13
            }

            // Enter hint + session pill share a row
            Row {
                spacing: 12
                anchors.left: parent.left

                // Session cycler (cycles through every installed session)
                Rectangle {
                    width: sessionLabel.implicitWidth + 34
                    height: 34
                    radius: 17
                    color: Qt.rgba(0.08, 0.10, 0.15, 0.6)
                    border.width: 1
                    border.color: Qt.rgba(0.55, 0.75, 0.92, 0.28)

                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: "󰍹"
                            color: "#9aa7b8"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            id: sessionLabel
                            text: root.currentSessionLabel
                            color: "#cfd8e4"
                            font.family: "Zenith Display"
                            font.pixelSize: 13
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cycleSession()
                    }
                }

                Text {
                    text: "Enter ↵"
                    color: Qt.rgba(0.72, 0.78, 0.86, 0.55)
                    font.family: "Zenith Display"
                    font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ------------------------------------------------------------------
    //  Top-left brand mark
    // ------------------------------------------------------------------
    Image {
        source: "file:///usr/share/sddm/themes/zenith/avatar.png"
        width: 56
        height: 56
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 40
        fillMode: Image.PreserveAspectFit
    }

    // ------------------------------------------------------------------
    //  Bottom-left: session name detail; Bottom-right: power actions
    // ------------------------------------------------------------------
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 28
        text: root.currentSession
        color: Qt.rgba(0.72, 0.78, 0.86, 0.45)
        font.family: "Zenith Display"
        font.pixelSize: 12
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28
        spacing: 14

        // Suspend (only when the greeter reports it is possible)
        PowerButton {
            label: "Suspend"
            visible: sddm.canSuspend !== undefined ? sddm.canSuspend : true
            onActivated: sddm.suspend()
        }
        PowerButton {
            label: "Reboot"
            onActivated: sddm.reboot()
        }
        PowerButton {
            label: "Shutdown"
            onActivated: sddm.powerOff()
        }
    }

    // ------------------------------------------------------------------
    component PowerButton: Rectangle {
        id: powerBtn
        signal activated()
        property string label: ""
        width: powerLabel.implicitWidth + 30
        height: 34
        radius: 17
        color: powerMouse.containsMouse
            ? Qt.rgba(0.55, 0.75, 0.92, 0.22)
            : Qt.rgba(0.08, 0.10, 0.15, 0.6)
        border.width: 1
        border.color: Qt.rgba(0.55, 0.75, 0.92, 0.28)

        Text {
            id: powerLabel
            anchors.centerIn: parent
            text: powerBtn.label
            color: "#e4ebf5"
            font.family: "Zenith Display"
            font.pixelSize: 13
        }
        MouseArea {
            id: powerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: powerBtn.activated()
        }
    }
}
