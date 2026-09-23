import QtQuick
import QtQuick.Controls.Basic
import Revenant

// Plain styled single-line input.
TextField {
    id: field

    implicitHeight: 38
    leftPadding: 14
    rightPadding: 14
    color: Theme.text
    placeholderTextColor: Theme.textFaint
    selectionColor: Theme.alpha(Theme.accent, 0.35)
    selectedTextColor: Theme.text
    font.pixelSize: 13
    verticalAlignment: TextInput.AlignVCenter

    background: Rectangle {
        radius: Theme.radiusM
        color: field.activeFocus ? Theme.raised : Theme.surface
        border.color: field.activeFocus ? Theme.alpha(Theme.accent, 0.6) : Theme.stroke
    }
}
