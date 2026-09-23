import QtQuick
import QtQuick.Layouts
import Revenant

// Editorial page heading: a small tracked eyebrow over a large serif title.
// The texts fill width so the heading can take up slack in a RowLayout
// (a nested layout never grows past what its children allow).
ColumnLayout {
    property string eyebrow
    property string title
    property string subtitle

    spacing: 2
    Text {
        Layout.fillWidth: true
        visible: text.length > 0
        text: parent.eyebrow.toUpperCase()
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 2.2
        color: Theme.accent
    }
    Text {
        Layout.fillWidth: true
        text: parent.title
        font.family: Theme.display
        font.pixelSize: 40
        font.weight: Font.Medium
        font.letterSpacing: -0.8
        color: Theme.text
    }
    Text {
        Layout.fillWidth: true
        visible: text.length > 0
        text: parent.subtitle
        font.pixelSize: 14
        color: Theme.textDim
    }
}
