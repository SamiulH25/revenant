import QtQuick
import QtQuick.Controls.Basic
import Revenant

// Pill search box. Emits accepted() on Enter; clears on Escape.
TextField {
    id: field

    implicitHeight: 40
    implicitWidth: 320
    leftPadding: 42
    rightPadding: clear.visible ? 40 : 16
    placeholderText: qsTr("Search")
    placeholderTextColor: Theme.textFaint
    color: Theme.text
    selectionColor: Theme.alpha(Theme.accent, 0.35)
    selectedTextColor: Theme.text
    font.pixelSize: 14
    verticalAlignment: TextInput.AlignVCenter

    background: Rectangle {
        radius: height / 2
        color: field.activeFocus ? Theme.raised : Theme.surface
        border.color: field.activeFocus ? Theme.alpha(Theme.accent, 0.6) : Theme.stroke
        Behavior on border.color { ColorAnimation { duration: Theme.fast } }
        Behavior on color { ColorAnimation { duration: Theme.fast } }

        Icon {
            anchors.left: parent.left
            anchors.leftMargin: 15
            anchors.verticalCenter: parent.verticalCenter
            glyph: Icons.search
            size: 16
            color: field.activeFocus ? Theme.accent : Theme.textFaint
        }
    }

    IconButton {
        id: clear
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 32
        implicitHeight: 32
        iconSize: 15
        glyph: Icons.x
        tint: Theme.textDim
        visible: field.text.length > 0
        onClicked: { field.clear(); field.accepted() }
    }

    Keys.onEscapePressed: event => {
        if (field.text.length > 0) { field.clear(); field.accepted(); event.accepted = true }
        else { field.focus = false; event.accepted = false }
    }
}
