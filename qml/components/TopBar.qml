import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import Revenant

// Floating top navigation. Transparent over hero art at the top of a page,
// frosting over once the page scrolls beneath it.
Item {
    id: bar

    property string current: "library"
    property int downloadBadge: 0
    property bool scrolled: false
    property Item backdrop
    signal navigate(string key)
    signal openSearch()

    readonly property var items: [
        { key: "library", label: qsTr("Library"), glyph: Icons.libraryBig },
        { key: "browse", label: qsTr("Discover"), glyph: Icons.compass },
        { key: "history", label: qsTr("History"), glyph: Icons.history },
        { key: "downloads", label: qsTr("Downloads"), glyph: Icons.download },
        { key: "extensions", label: qsTr("Extensions"), glyph: Icons.puzzle }
    ]

    height: Theme.navHeight

    GlassPanel {
        // Full-width frost once content scrolls under the bar.
        anchors.fill: parent
        backdrop: bar.backdrop
        tint: Theme.alpha(Theme.bg, 0.66)
        edge: false
        opacity: bar.scrolled ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.stroke }
    }

    Rectangle {
        // Darkens hero art just enough for the bar to read before it frosts.
        anchors.fill: parent
        anchors.bottomMargin: -40
        opacity: bar.scrolled ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.slow } }
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.45) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    // --- Wordmark ------------------------------------------------------------
    Row {
        id: brand
        anchors.left: parent.left
        anchors.leftMargin: Theme.gutter - 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Item {
            width: 34; height: 34
            anchors.verticalCenter: parent.verticalCenter
            Glow { anchors.centerIn: parent; width: 80; height: 80; strength: 0.3 }
            Icon {
                id: ghost
                anchors.centerIn: parent
                glyph: Icons.ghost
                size: 24
                color: Theme.accent
                // Idle haunting: a slow drift up and down.
                SequentialAnimation on anchors.verticalCenterOffset {
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.5; to: -1.5; duration: 1800; easing.type: Easing.InOutSine }
                    NumberAnimation { from: -1.5; to: 1.5; duration: 1800; easing.type: Easing.InOutSine }
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -1
            text: "Revenant"
            font.family: Theme.display
            font.italic: true
            font.pixelSize: 24
            font.weight: Font.DemiBold
            font.letterSpacing: -0.4
            color: Theme.text
        }
    }

    // --- Tabs ----------------------------------------------------------------
    Item {
        id: tabs
        anchors.centerIn: parent
        width: tabRow.width + 12
        height: 48

        GlassPanel {
            anchors.fill: parent
            radius: height / 2
            backdrop: bar.backdrop
            tint: Theme.alpha(Theme.surface, bar.scrolled ? 0.5 : 0.62)
        }

        Item {
            id: indicator
            readonly property Item target: {
                for (let i = 0; i < tabRep.count; ++i)
                    if (bar.items[i].key === bar.current) return tabRep.itemAt(i)
                return null
            }
            visible: target !== null
            x: target ? tabRow.x + target.x : 0
            width: target ? target.width : 0
            y: 6
            height: parent.height - 12
            Behavior on x { SpringAnimation { spring: 3.6; damping: 0.32; epsilon: 0.2 } }
            Behavior on width { SpringAnimation { spring: 3.6; damping: 0.32; epsilon: 0.2 } }

            RectangularShadow {
                anchors.fill: pillFill
                radius: pillFill.radius
                blur: 22
                spread: -2
                color: Theme.alpha(Theme.accent, 0.35)
            }
            Rectangle {
                id: pillFill
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.alpha(Theme.accent, 0.26) }
                    GradientStop { position: 1; color: Theme.alpha(Theme.accent, 0.14) }
                }
                border.color: Theme.alpha(Theme.accent, 0.45)
            }
        }

        Row {
            id: tabRow
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                id: tabRep
                model: bar.items
                delegate: AbstractButton {
                    id: tab
                    required property var modelData
                    readonly property bool active: bar.current === modelData.key
                    readonly property int badge: modelData.key === "downloads" ? bar.downloadBadge : 0
                    height: 36
                    width: tabContent.implicitWidth + 30
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: bar.navigate(modelData.key)

                    background: Rectangle {
                        radius: height / 2
                        color: !tab.active && tab.hovered ? Theme.hover : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                    }
                    contentItem: Item {
                        Row {
                            id: tabContent
                            anchors.centerIn: parent
                            spacing: 8
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: tab.modelData.glyph
                                size: 16
                                color: tab.active ? Theme.accent : tab.hovered ? Theme.text : Theme.textDim
                                scale: tab.pressed ? 0.85 : 1
                                Behavior on color { ColorAnimation { duration: Theme.fast } }
                                Behavior on scale { NumberAnimation { duration: Theme.fast } }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tab.modelData.label
                                font.pixelSize: 14
                                font.weight: tab.active ? Font.DemiBold : Font.Medium
                                color: tab.active ? Theme.text : tab.hovered ? Theme.text : Theme.textDim
                                Behavior on color { ColorAnimation { duration: Theme.fast } }
                            }
                            Rectangle {
                                visible: tab.badge > 0
                                anchors.verticalCenter: parent.verticalCenter
                                height: 18
                                width: Math.max(18, badgeText.implicitWidth + 10)
                                radius: 9
                                color: Theme.accent
                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: tab.badge > 99 ? "99+" : tab.badge
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: Theme.accentInk
                                }
                                SequentialAnimation on scale {
                                    running: tab.badge > 0
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 1.12; duration: 700; easing.type: Easing.InOutSine }
                                    NumberAnimation { from: 1.12; to: 1; duration: 700; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Right cluster ---------------------------------------------------------
    RowLayout {
        anchors.right: parent.right
        anchors.rightMargin: Theme.gutter - 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        AbstractButton {
            id: searchButton
            implicitHeight: 40
            implicitWidth: searchRow.implicitWidth + 30
            hoverEnabled: true
            focusPolicy: Qt.NoFocus
            onClicked: bar.openSearch()
            background: Item {
                GlassPanel {
                    anchors.fill: parent
                    radius: height / 2
                    backdrop: bar.backdrop
                    tint: searchButton.hovered ? Theme.alpha(Theme.raised, 0.8) : Theme.alpha(Theme.surface, 0.62)
                    edgeColor: searchButton.hovered ? Theme.alpha(Theme.accent, 0.4) : Theme.glassEdge
                }
            }
            contentItem: Item {
                Row {
                    id: searchRow
                    anchors.centerIn: parent
                    spacing: 10
                    Icon { anchors.verticalCenter: parent.verticalCenter; glyph: Icons.search; size: 15; color: searchButton.hovered ? Theme.accent : Theme.textDim }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Search")
                        font.pixelSize: 14
                        color: Theme.textDim
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: kbd.implicitWidth + 12
                        height: 22
                        radius: 6
                        color: Theme.alpha("#FFFFFF", 0.06)
                        border.color: Theme.stroke
                        Text {
                            id: kbd
                            anchors.centerIn: parent
                            text: "Ctrl K"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: Theme.textFaint
                        }
                    }
                }
            }
        }

        Item {
            implicitWidth: 40
            implicitHeight: 40
            GlassPanel {
                anchors.fill: parent
                radius: 20
                backdrop: bar.backdrop
                tint: bar.current === "settings" ? Theme.alpha(Theme.accent, 0.18) : Theme.alpha(Theme.surface, 0.62)
                edgeColor: bar.current === "settings" ? Theme.alpha(Theme.accent, 0.45) : Theme.glassEdge
            }
            IconButton {
                anchors.fill: parent
                glyph: Icons.settings
                tip: qsTr("Settings (Ctrl+,)")
                tint: bar.current === "settings" ? Theme.accent : Theme.textDim
                onClicked: bar.navigate("settings")
                RotationAnimator on rotation {
                    running: bar.current === "settings"
                    from: 0; to: 90; duration: 600
                    easing.type: Easing.OutBack
                }
            }
            Rectangle {
                // Server health: mint when connected, amber while starting, red on failure.
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 2
                width: 9; height: 9; radius: 4.5
                border.width: 2
                border.color: Theme.bg
                color: ServerManager.state === ServerManager.Ready ? Theme.accent
                     : ServerManager.state === ServerManager.Failed ? Theme.danger : Theme.warning
                ToolTip.visible: statusHover.hovered
                ToolTip.text: ServerManager.statusText
                HoverHandler { id: statusHover }
            }
        }
    }
}
