import QtQuick
import QtQuick.Controls.Basic
import Revenant

// Styled ComboBox. model is an array of strings, or objects with textRole /
// valueRole set.
ComboBox {
    id: box

    implicitHeight: 36
    implicitWidth: 200
    font.pixelSize: 13

    background: Rectangle {
        radius: height / 2
        color: box.hovered ? Theme.raised : Theme.surface
        border.color: box.activeFocus ? Theme.alpha(Theme.accent, 0.6) : Theme.stroke
    }
    contentItem: Text {
        leftPadding: 16
        rightPadding: 32
        text: box.displayText
        font: box.font
        color: Theme.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Icon {
        x: box.width - width - 12
        anchors.verticalCenter: parent.verticalCenter
        glyph: Icons.chevronDown
        size: 14
        color: Theme.textDim
    }
    popup: Popup {
        y: box.height + 6
        width: Math.max(box.width, 180)
        height: Math.min(contentItem.implicitHeight + 12, 420)
        padding: 6
        background: Rectangle { radius: Theme.radiusM; color: Theme.overlay; border.color: Theme.strokeStrong }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: box.delegateModel
            currentIndex: box.highlightedIndex
            ScrollBar.vertical: ScrollBar {}
        }
    }
    delegate: ItemDelegate {
        id: option
        required property var modelData
        required property int index
        width: ListView.view ? ListView.view.width : box.width
        height: 34
        highlighted: box.highlightedIndex === index
        background: Rectangle { radius: Theme.radiusS; color: option.highlighted ? Theme.hover : "transparent" }
        contentItem: Text {
            leftPadding: 4
            text: box.textRole ? option.modelData[box.textRole] : option.modelData
            font.pixelSize: 13
            elide: Text.ElideRight
            color: box.currentIndex === option.index ? Theme.accent : Theme.text
            verticalAlignment: Text.AlignVCenter
        }
    }
}
