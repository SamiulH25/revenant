import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

// Modal dialog: title, scrollable body, optional footer. Children go into the
// body column; put buttons in `footer`.
Popup {
    id: sheet

    property string title
    property string subtitle
    property real preferredWidth: 520
    default property alias content: body.data
    property alias footerItems: footerRow.data
    property bool busy: false

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(preferredWidth, parent ? parent.width - 48 : preferredWidth)
    height: Math.min(frame.implicitHeight, parent ? parent.height - 64 : 600)
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.6)
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.fast }
    }

    background: Rectangle {
        radius: Theme.radiusXL
        color: Theme.raised
        border.color: Theme.strokeStrong
    }

    contentItem: ColumnLayout {
        id: frame
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 24
            Layout.bottomMargin: 12
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: sheet.title
                    elide: Text.ElideRight
                    font.family: Theme.display
                    font.pixelSize: 24
                    font.weight: Font.Medium
                    color: Theme.text
                }
                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: sheet.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: 12
                    color: Theme.textFaint
                }
            }
            Spinner { visible: sheet.busy; size: 18 }
            IconButton { glyph: Icons.x; tip: qsTr("Close"); onClicked: sheet.close() }
        }

        ScrollView {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: body.implicitHeight
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                id: body
                width: scroller.availableWidth - 48
                x: 24
                spacing: 12
            }
        }

        RowLayout {
            id: footerRow
            Layout.fillWidth: true
            Layout.margins: 24
            Layout.topMargin: 16
            spacing: 10
            visible: children.length > 0
        }
    }
}
