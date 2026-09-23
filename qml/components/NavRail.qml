import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

// Left navigation rail with a sliding active marker.
Rectangle {
    id: rail

    property string current: "library"
    property int downloadBadge: 0
    signal navigate(string key)

    readonly property var items: [
        { key: "library", label: qsTr("Library"), glyph: Icons.libraryBig },
        { key: "browse", label: qsTr("Browse"), glyph: Icons.compass },
        { key: "history", label: qsTr("History"), glyph: Icons.history },
        { key: "downloads", label: qsTr("Downloads"), glyph: Icons.download },
        { key: "extensions", label: qsTr("Extensions"), glyph: Icons.puzzle }
    ]

    width: Theme.navWidth
    color: Theme.ink

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.stroke
    }

    Text {
        id: logo
        anchors.horizontalCenter: parent.horizontalCenter
        y: 22
        text: "R"
        font.family: Theme.display
        font.italic: true
        font.pixelSize: 34
        font.weight: Font.DemiBold
        color: Theme.accent
    }

    Rectangle {
        id: marker
        readonly property Item target: {
            for (let i = 0; i < navRep.count; ++i)
                if (rail.items[i].key === rail.current) return navRep.itemAt(i)
            return rail.current === "settings" ? settingsItem : null
        }
        visible: target !== null
        x: 0
        y: target ? target.parent.y + target.y + 14 : 0
        width: 3
        height: 30
        radius: 2
        color: Theme.accent
        Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
    }

    // Takes everything from its use sites: inline components can't see
    // the enclosing file's ids.
    component NavItem: AbstractButton {
        id: item
        property string key
        property string glyph
        property bool active
        property int badge: 0
        height: 58
        hoverEnabled: true
        focusPolicy: Qt.NoFocus

        background: Rectangle {
            anchors.centerIn: parent
            width: 48
            height: 48
            radius: Theme.radiusM
            color: item.active ? Theme.alpha(Theme.accent, 0.1) : item.hovered ? Theme.hover : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
        contentItem: Item {
            Icon {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -7
                glyph: item.glyph
                size: 20
                color: item.active ? Theme.accent : item.hovered ? Theme.text : Theme.textDim
            }
            Rectangle {
                visible: item.badge > 0
                x: parent.width / 2 + 4
                y: 6
                height: 16
                width: Math.max(16, badgeText.implicitWidth + 8)
                radius: 8
                color: Theme.accent
                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: item.badge > 99 ? "99+" : item.badge
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Theme.accentInk
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                text: item.text
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 0.3
                color: item.active ? Theme.text : Theme.textFaint
            }
        }
    }

    Column {
        anchors.top: logo.bottom
        anchors.topMargin: 26
        width: parent.width
        spacing: 4
        Repeater {
            id: navRep
            model: rail.items
            NavItem {
                required property var modelData
                width: rail.width
                key: modelData.key
                glyph: modelData.glyph
                text: modelData.label
                active: rail.current === key
                badge: key === "downloads" ? rail.downloadBadge : 0
                onClicked: rail.navigate(key)
            }
        }
    }

    Column {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        width: parent.width
        spacing: 8

        NavItem {
            id: settingsItem
            width: rail.width
            key: "settings"
            glyph: Icons.settings
            text: qsTr("Settings")
            active: rail.current === key
            onClicked: rail.navigate(key)
        }

        Rectangle {
            // Server health: mint when connected, amber while starting, red on failure.
            anchors.horizontalCenter: parent.horizontalCenter
            width: 8; height: 8; radius: 4
            color: ServerManager.state === ServerManager.Ready ? Theme.accent
                 : ServerManager.state === ServerManager.Failed ? Theme.danger : Theme.warning
            ToolTip.visible: statusHover.containsMouse
            ToolTip.text: ServerManager.statusText
            MouseArea { id: statusHover; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true }
        }
    }
}
