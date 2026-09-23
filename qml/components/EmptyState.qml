import QtQuick
import QtQuick.Layouts
import Revenant

ColumnLayout {
    id: empty
    property string glyph: Icons.ghost
    property string title
    property string body
    default property alias actions: actionRow.data

    spacing: 10
    Icon {
        Layout.alignment: Qt.AlignHCenter
        glyph: empty.glyph
        size: 44
        color: Theme.textFaint
        Layout.bottomMargin: 6
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: empty.title
        font.family: Theme.display
        font.pixelSize: 24
        color: Theme.text
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: 420
        text: empty.body
        visible: text.length > 0
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: 14
        lineHeight: 1.3
        color: Theme.textDim
    }
    RowLayout {
        id: actionRow
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 10
        spacing: 10
    }
}
