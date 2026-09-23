import QtQuick
import QtQuick.Controls.Basic
import Revenant

// Pill switch.
Switch {
    id: sw

    implicitWidth: 46
    implicitHeight: 26
    padding: 0
    focusPolicy: Qt.NoFocus

    indicator: Rectangle {
        implicitWidth: 46
        implicitHeight: 26
        radius: 13
        color: sw.checked ? Theme.accent : Theme.overlay
        border.color: sw.checked ? Theme.accent : Theme.strokeStrong
        opacity: sw.enabled ? 1 : 0.4
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Rectangle {
            x: sw.checked ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20; radius: 10
            color: sw.checked ? Theme.accentInk : Theme.textDim
            Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
        }
    }
    contentItem: null
}
