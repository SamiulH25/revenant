import QtQuick
import QtQuick.Controls.Basic
import Revenant

// Styled context menu. Declare entries as Action { text; onTriggered } so the
// delegate below renders them; MenuSeparator works too.
Menu {
    id: menu

    padding: 6
    background: Rectangle {
        implicitWidth: 240
        radius: Theme.radiusM
        color: Theme.overlay
        border.color: Theme.strokeStrong
    }
    delegate: MenuItem {
        id: mi
        implicitHeight: 36
        background: Rectangle { radius: Theme.radiusS; color: mi.highlighted ? Theme.hover : "transparent" }
        contentItem: Text {
            leftPadding: 8
            text: mi.text
            color: mi.enabled ? Theme.text : Theme.textFaint
            font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
        }
    }
}
