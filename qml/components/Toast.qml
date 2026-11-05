import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Revenant

// Transient message that springs up from the bottom edge. A thin bar along
// the bottom drains while it waits to leave; hovering holds it.
Item {
    id: toast

    function show(message, kind) {
        // One line only: messages can carry server stack traces.
        label.text = String(message).split("\n")[0]
        toast.kind = kind || "info"
        state = "shown"
        drain.restart()
    }

    property string kind: "info"
    readonly property color tone: kind === "error" ? Theme.danger : Theme.accent
    readonly property int life: kind === "error" ? 5600 : 2800

    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height + 20
    width: Math.min(row.implicitWidth + 44, parent.width - 80)
    height: 48
    opacity: 0
    scale: 0.92
    z: 1000

    states: State {
        name: "shown"
        PropertyChanges { toast.y: toast.parent.height - toast.height - 32; toast.opacity: 1; toast.scale: 1 }
    }
    transitions: [
        Transition {
            to: "shown"
            NumberAnimation { property: "y"; duration: Theme.slower; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            NumberAnimation { properties: "opacity,scale"; duration: Theme.normal; easing.type: Easing.OutCubic }
        },
        Transition {
            NumberAnimation { properties: "y,opacity,scale"; duration: Theme.normal; easing.type: Easing.InCubic }
        }
    ]

    RectangularShadow {
        anchors.fill: pill
        radius: pill.radius
        blur: 30
        offset.y: 12
        color: Qt.rgba(0, 0, 0, 0.6)
    }

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: height / 2
        color: Theme.glassStrong
        border.color: toast.kind === "error" ? Theme.alpha(Theme.danger, 0.45) : Theme.glassEdge
        clip: true

        Rectangle {
            id: bar
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            height: 2
            color: Theme.alpha(toast.tone, 0.7)
            NumberAnimation on width {
                id: drain
                running: false
                from: pill.width
                to: 0
                duration: toast.life
                paused: running && holder.hovered
                onFinished: toast.state = ""
            }
        }
    }

    HoverHandler { id: holder }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 10
        Rectangle {
            width: 22; height: 22; radius: 11
            color: Theme.alpha(toast.tone, 0.16)
            Icon {
                anchors.centerIn: parent
                glyph: toast.kind === "error" ? Icons.circleAlert : Icons.circleCheck
                color: toast.tone
                size: 14
            }
        }
        Text {
            id: label
            color: Theme.text
            font.pixelSize: 14
            font.weight: Font.Medium
            maximumLineCount: 1
            elide: Text.ElideRight
            Layout.maximumWidth: toast.parent ? toast.parent.width - 170 : 600
        }
    }
}
