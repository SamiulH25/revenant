import QtQuick
import QtQuick.Effects
import Revenant

// Full-bleed cinematic backdrop: cover art blurred into a wash of colour,
// crossfading when the source changes and drifting slowly (Ken Burns), with
// a fade into the page background at the bottom and a shade on the left
// so text set over it reads.
Item {
    id: root

    property string source
    property color tint: Theme.accent
    property real intensity: 0.62
    property real blurAmount: 1.0
    property bool sideShade: true
    property real fadeStart: 0.45
    // Fade into the page background at the bottom.
    property bool fade: true
    // Strength of the tint wash over the art.
    property real wash: 0.1

    property int front: 0
    property var srcs: ["", ""]

    clip: true

    onSourceChanged: {
        if (source === srcs[front])
            return
        const next = 1 - front
        const s = srcs.slice()
        s[next] = source
        srcs = s
        front = next
    }

    Item {
        id: drift
        anchors.fill: parent
        transformOrigin: Item.Center
        SequentialAnimation on scale {
            loops: Animation.Infinite
            running: Theme.ambientMotion && root.visible
            NumberAnimation { from: 1.08; to: 1.2; duration: 26000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.2; to: 1.08; duration: 26000; easing.type: Easing.InOutSine }
        }

        Repeater {
            model: 2
            Item {
                id: layer
                required property int index
                anchors.fill: parent
                opacity: root.front === index && art.status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.cinematic; easing.type: Easing.InOutQuad } }

                Image {
                    id: art
                    anchors.fill: parent
                    source: root.srcs[layer.index]
                    sourceSize.width: 320
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: art
                    blurEnabled: true
                    blur: root.blurAmount
                    blurMax: 64
                    saturation: 0.35
                    brightness: -0.05
                    opacity: root.intensity
                }
            }
        }
    }

    Rectangle {
        // Tint wash so even grey art carries the title's colour.
        anchors.fill: parent
        color: Theme.alpha(root.tint, root.wash)
        Behavior on color { ColorAnimation { duration: Theme.cinematic } }
    }

    Rectangle {
        visible: root.sideShade
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.alpha(Theme.bg, 0.82) }
            GradientStop { position: 0.55; color: Theme.alpha(Theme.bg, 0.35) }
            GradientStop { position: 1; color: Theme.alpha(Theme.bg, 0.15) }
        }
    }

    Rectangle {
        visible: root.fade
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.alpha(Theme.bg, 0.2) }
            GradientStop { position: root.fadeStart; color: Theme.alpha(Theme.bg, 0.45) }
            GradientStop { position: 1; color: Theme.bg }
        }
    }
}
