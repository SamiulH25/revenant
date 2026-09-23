import QtQuick
import Revenant

Text {
    property alias glyph: icon.text
    property real size: 18

    id: icon
    font.family: Theme.icons
    font.pixelSize: size
    color: Theme.text
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.CurveRendering
}
