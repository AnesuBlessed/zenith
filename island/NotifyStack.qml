import QtQuick
import "../core"
import "../services"

// Drip-style presentation of the native notification stack. The Rust engine
// supplies already-spring-sampled positions and opacities, so QML only places
// the cards on the existing island surface.
Item {
    id: root

    HoverHandler {
        onHoveredChanged: hovered ? NotificationBridge.hold()
            : NotificationBridge.release()
    }

    Repeater {
        model: NotificationBridge.cards
        delegate: NotifyCard {}
    }

    Text {
        visible: NotificationBridge.overflow > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: Config.notifications.cardHeight * Config.notifications.stackMax
            + Config.notifications.cardGap
        text: "+" + NotificationBridge.overflow + " more"
        color: Theme.surfaceVariantText
        font.family: Config.appearance.fontFamily
        font.pixelSize: Theme.textSmall
    }
}
