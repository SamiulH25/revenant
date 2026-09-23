import QtQuick
import QtQuick.Layouts
import Revenant

// Transient message at the bottom of the window.
Rectangle {
    id: toast

    function show(message, kind) {
        label.text = message
        toast.kind = kind || "info"
        state = "shown"
        hideTimer.restart()
    }

    property string kind: "info"

    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height
    width: Math.min(row.implicitWidth + 40, parent.width - 80)
    height: 46
    radius: 23
    color: Theme.overlay
    border.color: kind === "error" ? Theme.alpha(Theme.danger, 0.5) : Theme.strokeStrong
    opacity: 0
    z: 1000

    states: State {
        name: "shown"
        PropertyChanges { toast.y: toast.parent.height - toast.height - 28; toast.opacity: 1 }
    }
    transitions: Transition {
        NumberAnimation { properties: "y,opacity"; duration: Theme.normal; easing.type: Easing.OutQuint }
    }

    Timer { id: hideTimer; interval: toast.kind === "error" ? 5200 : 2800; onTriggered: toast.state = "" }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 10
        Icon {
            glyph: toast.kind === "error" ? Icons.circleAlert : Icons.circleCheck
            color: toast.kind === "error" ? Theme.danger : Theme.accent
            size: 16
        }
        Text {
            id: label
            color: Theme.text
            font.pixelSize: 14
            elide: Text.ElideRight
            Layout.maximumWidth: toast.parent.width - 160
        }
    }
}
