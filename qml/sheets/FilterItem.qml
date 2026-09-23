import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

// One leaf source filter (anything but a group). Check boxes and tri-states
// are compact chips so groups of them flow; the rest take the full width.
Item {
    id: item

    property var filter
    property var value
    property real fullWidth: 300
    signal edited(var value)

    readonly property string kind: filter ? filter.__typename : ""
    readonly property bool compact: kind === "CheckBoxFilter" || kind === "TriStateFilter"

    width: compact ? chip.implicitWidth : fullWidth
    implicitHeight: compact ? chip.implicitHeight
                  : kind === "SeparatorFilter" ? 17
                  : kind === "HeaderFilter" ? header.implicitHeight + 6
                  : column.implicitHeight

    // --- Check box / tri-state chip ---------------------------------------
    AbstractButton {
        id: chip
        visible: item.compact
        readonly property string tri: item.kind === "TriStateFilter" ? item.value : (item.value ? "INCLUDE" : "IGNORE")
        implicitHeight: 30
        implicitWidth: chipRow.implicitWidth + 22
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        onClicked: {
            if (item.kind === "CheckBoxFilter")
                item.edited(!item.value)
            else
                item.edited(item.value === "IGNORE" ? "INCLUDE" : item.value === "INCLUDE" ? "EXCLUDE" : "IGNORE")
        }
        background: Rectangle {
            radius: height / 2
            color: chip.tri === "INCLUDE" ? Theme.alpha(Theme.accent, 0.16)
                 : chip.tri === "EXCLUDE" ? Theme.alpha(Theme.danger, 0.14)
                 : chip.hovered ? Theme.hover : "transparent"
            border.color: chip.tri === "INCLUDE" ? Theme.alpha(Theme.accent, 0.55)
                        : chip.tri === "EXCLUDE" ? Theme.alpha(Theme.danger, 0.5) : Theme.stroke
        }
        contentItem: Item {
            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 5
                Icon {
                    visible: chip.tri !== "IGNORE"
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: chip.tri === "EXCLUDE" ? Icons.x : Icons.check
                    size: 12
                    color: chip.tri === "EXCLUDE" ? Theme.danger : Theme.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: item.filter ? item.filter.name : ""
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    font.strikeout: chip.tri === "EXCLUDE"
                    color: chip.tri === "INCLUDE" ? Theme.accent : chip.tri === "EXCLUDE" ? Theme.danger : Theme.textDim
                }
            }
        }
    }

    // --- Header / separator -------------------------------------------------
    Text {
        id: header
        visible: item.kind === "HeaderFilter"
        width: item.fullWidth
        topPadding: 6
        text: item.filter && item.filter.name ? item.filter.name : ""
        wrapMode: Text.WordWrap
        font.pixelSize: 12
        color: Theme.textFaint
    }
    Rectangle {
        visible: item.kind === "SeparatorFilter"
        y: 8
        width: item.fullWidth
        height: 1
        color: Theme.stroke
    }

    // --- Text / select / sort ---------------------------------------------
    ColumnLayout {
        id: column
        visible: item.kind === "TextFilter" || item.kind === "SelectFilter" || item.kind === "SortFilter"
        width: item.fullWidth
        spacing: 8

        Text {
            text: item.filter ? item.filter.name : ""
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: Theme.text
        }

        TextBox {
            Layout.fillWidth: true
            visible: item.kind === "TextFilter"
            text: item.kind === "TextFilter" ? (item.value || "") : ""
            onTextEdited: item.edited(text)
        }

        Dropdown {
            Layout.fillWidth: true
            visible: item.kind === "SelectFilter"
            model: item.kind === "SelectFilter" ? item.filter.values : []
            currentIndex: item.kind === "SelectFilter" ? (item.value ?? 0) : -1
            onActivated: index => item.edited(index)
        }

        Flow {
            Layout.fillWidth: true
            visible: item.kind === "SortFilter"
            spacing: 6
            Repeater {
                model: item.kind === "SortFilter" ? item.filter.values : []
                Chip {
                    required property string modelData
                    required property int index
                    readonly property bool selected: !!item.value && item.value.index === index
                    checkable: false
                    checked: selected
                    text: modelData + (selected ? (item.value.ascending ? "  ↑" : "  ↓") : "")
                    onClicked: item.edited({ index: index, ascending: selected ? !item.value.ascending : false })
                }
            }
        }
    }
}
