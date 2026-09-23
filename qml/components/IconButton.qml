import QtQuick
import QtQuick.Controls.Basic
import Revenant

// Circular icon-only button with hover wash and tooltip.
AbstractButton {
    id: control

    property string glyph
    property string tip
    property color tint: Theme.text
    property real iconSize: 18
    property bool filled: false

    implicitWidth: 38
    implicitHeight: 38
    hoverEnabled: true
    focusPolicy: Qt.NoFocus

    background: Rectangle {
        radius: height / 2
        color: control.filled ? Theme.alpha(Theme.overlay, 0.85)
             : control.pressed ? Theme.pressed
             : control.hovered ? Theme.hover : "transparent"
        border.color: control.filled ? Theme.stroke : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    contentItem: Icon {
        glyph: control.glyph
        size: control.iconSize
        color: control.enabled ? (control.checked ? Theme.accent : control.tint) : Theme.textFaint
        scale: control.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
    }

    ToolTip.visible: tip.length > 0 && hovered
    ToolTip.delay: 500
    ToolTip.text: tip
}
