import QtQuick
import QtQuick.Controls.Basic
import Revenant

// Small toggleable filter chip.
AbstractButton {
    id: control

    property color accent: Theme.accent

    checkable: true
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    implicitHeight: 30
    implicitWidth: label.implicitWidth + 24

    background: Rectangle {
        radius: height / 2
        color: control.checked ? Theme.alpha(control.accent, 0.16) : control.hovered ? Theme.hover : "transparent"
        border.color: control.checked ? Theme.alpha(control.accent, 0.55) : Theme.stroke
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    contentItem: Text {
        id: label
        text: control.text
        font.pixelSize: 13
        font.weight: Font.Medium
        color: control.checked ? control.accent : Theme.textDim
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
