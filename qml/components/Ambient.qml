import QtQuick
import QtQuick.Effects
import Revenant

// Full-bleed backdrop: the cover, heavily blurred and darkened, washing the
// top of the page in the title's own colours.
Item {
    id: root

    property string source
    property color tint: Theme.accent

    clip: true

    Image {
        id: art
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 1.2
        height: Math.max(parent.height * 0.9, 520)
        y: -height * 0.15
        source: root.source
        sourceSize.width: 256
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: art
        source: art
        blurEnabled: true
        blurMax: 64
        blur: 1.0
        saturation: 0.25
        brightness: -0.08
        opacity: art.status === Image.Ready ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.slow } }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.alpha(Theme.bg, 0.35) }
            GradientStop { position: 0.45; color: Theme.alpha(Theme.bg, 0.86) }
            GradientStop { position: 0.72; color: Theme.bg }
        }
    }

    Rectangle {
        // A faint wash of the extracted accent along the top edge.
        anchors.left: parent.left
        anchors.right: parent.right
        height: 260
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.alpha(root.tint, 0.14) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
}
