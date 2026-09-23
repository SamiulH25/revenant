import QtQuick
import Revenant

// Segmented control with a sliding thumb. model: [{ value, label, glyph? }]
Rectangle {
    id: root

    property var model: []
    property var value
    signal activated(var value)

    readonly property int currentIndex: {
        for (let i = 0; i < model.length; ++i)
            if (model[i].value === value) return i
        return -1
    }

    implicitHeight: 36
    implicitWidth: row.implicitWidth + 8
    radius: height / 2
    color: Theme.surface
    border.color: Theme.stroke

    Rectangle {
        id: thumb
        // rep.count makes this re-evaluate once the delegates exist.
        readonly property Item target: rep.count > 0 && root.currentIndex >= 0 ? rep.itemAt(root.currentIndex) : null
        visible: target !== null
        x: target ? row.x + target.x : 0
        width: target ? target.width : 0
        y: 4
        height: parent.height - 8
        radius: height / 2
        color: Theme.overlay
        border.color: Theme.strokeStrong
        Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
    }

    Row {
        id: row
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            id: rep
            model: root.model
            delegate: MouseArea {
                id: segItem
                required property var modelData
                required property int index
                width: seg.implicitWidth + 28
                height: root.height - 8
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.value = segItem.modelData.value; root.activated(segItem.modelData.value) }
                Row {
                    id: seg
                    anchors.centerIn: parent
                    spacing: 6
                    Icon {
                        visible: !!segItem.modelData.glyph
                        glyph: segItem.modelData.glyph || ""
                        size: 14
                        color: segItem.index === root.currentIndex ? Theme.accent : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: segItem.modelData.label
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: segItem.index === root.currentIndex ? Theme.text : Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                    }
                }
            }
        }
    }
}
