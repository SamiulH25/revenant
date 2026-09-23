import QtQuick
import QtQuick.Effects
import Revenant

// Rounded cover art with a shimmer placeholder and fade-in.
Item {
    id: root

    property alias source: img.source
    property real radius: Theme.radiusM
    property int decodeWidth: Math.ceil(width * Screen.devicePixelRatio)
    readonly property bool ready: img.status === Image.Ready

    Rectangle {
        id: placeholder
        anchors.fill: parent
        radius: root.radius
        color: Theme.raised
        visible: !root.ready
        clip: true

        Rectangle {
            id: sheen
            width: parent.width * 0.7
            height: parent.height * 1.6
            rotation: 18
            y: -parent.height * 0.3
            visible: img.status === Image.Loading
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.045) }
                GradientStop { position: 1; color: "transparent" }
            }
            NumberAnimation on x {
                running: sheen.visible
                from: -root.width
                to: root.width * 1.4
                duration: 1400
                loops: Animation.Infinite
                easing.type: Easing.InOutSine
            }
        }

        Icon {
            anchors.centerIn: parent
            visible: img.status === Image.Error || img.source.toString() === ""
            glyph: Icons.imageOff
            size: Math.min(28, root.width / 4)
            color: Theme.textFaint
        }
    }

    Image {
        id: img
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: root.decodeWidth
        opacity: root.ready ? 1 : 0
        visible: false
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
    }

    MultiEffect {
        anchors.fill: img
        source: img
        opacity: img.opacity
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }

    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        visible: false
        Rectangle {
            anchors.fill: parent
            radius: root.radius
        }
    }
}
