import QtQuick
import QtQuick.Layouts
import Revenant

// Grid tile: 2:3 cover with hover lift, unread badge and a library marker.
Item {
    id: card

    property var manga
    property string subtitle
    property bool showLibraryMark: true
    signal clicked()

    implicitWidth: Prefs.coverSize
    implicitHeight: coverFrame.height + titleText.implicitHeight + (subtitle.length ? 18 : 0) + 14

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.clicked()
    }

    Item {
        id: coverFrame
        width: parent.width
        height: Math.round(width * 1.5)
        y: hover.containsMouse ? -4 : 0
        Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }

        Rectangle {
            // Soft accent glow on hover.
            anchors.fill: parent
            anchors.margins: -1
            radius: Theme.radiusM + 1
            color: "transparent"
            border.width: 1
            border.color: hover.containsMouse ? Theme.alpha(Theme.accent, 0.55) : Theme.stroke
            Behavior on border.color { ColorAnimation { duration: Theme.normal } }
        }

        Cover {
            id: cover
            anchors.fill: parent
            source: Api.mangaCover(card.manga)
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusM
            opacity: hover.containsMouse ? 0.0 : 0.25
            gradient: Gradient {
                GradientStop { position: 0.55; color: "transparent" }
                GradientStop { position: 1.0; color: Theme.ink }
            }
            Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        }

        Rectangle {
            visible: !!card.manga && card.manga.unreadCount > 0
            anchors { left: parent.left; top: parent.top; margins: 8 }
            height: 22
            width: Math.max(22, unread.implicitWidth + 12)
            radius: 11
            color: Theme.accent
            Text {
                id: unread
                anchors.centerIn: parent
                text: card.manga ? card.manga.unreadCount : ""
                font.pixelSize: 12
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
                color: Theme.accentInk
            }
        }

        Rectangle {
            visible: !!(card.showLibraryMark && card.manga && card.manga.inLibrary)
            anchors { right: parent.right; top: parent.top; margins: 8 }
            width: 26; height: 26; radius: 13
            color: Theme.alpha(Theme.ink, 0.72)
            border.color: Theme.alpha(Theme.accent, 0.6)
            Icon { anchors.centerIn: parent; glyph: Icons.bookMarked; size: 13; color: Theme.accent }
        }
    }

    ColumnLayout {
        anchors.top: coverFrame.bottom
        anchors.topMargin: 10
        width: parent.width
        spacing: 3
        Text {
            id: titleText
            Layout.fillWidth: true
            text: card.manga ? card.manga.title : ""
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            font.pixelSize: 13
            font.weight: Font.Medium
            lineHeight: 1.15
            color: hover.containsMouse ? Theme.text : Theme.alpha(Theme.text, 0.88)
        }
        Text {
            Layout.fillWidth: true
            visible: card.subtitle.length > 0
            text: card.subtitle
            elide: Text.ElideRight
            font.pixelSize: 12
            color: Theme.textFaint
        }
    }
}
