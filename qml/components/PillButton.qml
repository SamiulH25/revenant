import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

// Rounded text button. "primary" fills with the accent; otherwise a quiet
// outlined pill.
AbstractButton {
    id: control

    property string glyph
    property bool primary: false
    property bool busy: false
    property color accent: Theme.accent

    implicitHeight: 40
    implicitWidth: row.implicitWidth + 36
    hoverEnabled: true
    focusPolicy: Qt.NoFocus

    background: Rectangle {
        radius: height / 2
        color: control.primary
               ? (control.pressed ? Qt.darker(control.accent, 1.15) : control.hovered ? Qt.lighter(control.accent, 1.08) : control.accent)
               : (control.pressed ? Theme.pressed : control.hovered ? Theme.hover : "transparent")
        border.width: control.primary ? 0 : 1
        border.color: control.checked ? control.accent : Theme.strokeStrong
        opacity: control.enabled ? 1 : 0.4
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    contentItem: Item {
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Spinner {
                visible: control.busy
                size: 16
                color: control.primary ? Theme.accentInk : control.accent
            }
            Icon {
                visible: !control.busy && control.glyph.length > 0
                glyph: control.glyph
                size: 16
                color: control.primary ? Theme.accentInk : (control.checked ? control.accent : Theme.text)
            }
            Text {
                text: control.text
                visible: text.length > 0
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: control.primary ? Theme.accentInk : (control.checked ? control.accent : Theme.text)
            }
        }
    }

    scale: pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
}
