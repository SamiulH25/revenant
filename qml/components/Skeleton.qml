import QtQuick
import Revenant

// Placeholder block with a travelling sheen, for content still on its way.
Rectangle {
    id: root

    property int delay: 0

    radius: Theme.radiusM
    color: Theme.raised
    clip: true

    Rectangle {
        id: sheen
        width: root.width * 0.8
        height: root.height * 2
        y: -root.height / 2
        rotation: 16
        x: -width
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.05) }
            GradientStop { position: 1; color: "transparent" }
        }
        SequentialAnimation on x {
            loops: Animation.Infinite
            PauseAnimation { duration: root.delay }
            NumberAnimation { from: -sheen.width; to: root.width * 1.3; duration: 1500; easing.type: Easing.InOutSine }
            PauseAnimation { duration: 300 }
        }
    }
}
