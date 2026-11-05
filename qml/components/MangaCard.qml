import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Revenant

// Grid tile: a 2:3 cover that tilts toward the pointer in 3D, catches a
// glare where the light would hit, glows in the cover's own colour, and
// rises into place when it first appears.
Item {
    id: card

    property var manga
    property string subtitle
    property bool showLibraryMark: true
    // Fraction of the series read, 0..1; negative hides the bar.
    property real progress: -1
    // Shows a play button on hover; emits play().
    property bool playable: false
    // Milliseconds to wait before rising in; negative appears at once.
    property int enterDelay: -1
    property bool selected: false
    // Hide the caption when the card stands alone (heroes, peeks).
    property bool showTitle: true

    signal clicked()
    signal play()
    signal menu()

    readonly property bool hot: hover.containsMouse || selected
    property real px: 0.5
    property real py: 0.5
    property color glow: Theme.accent
    property bool glowRequested: false

    implicitWidth: Prefs.coverSize
    implicitHeight: lift.height + (showTitle ? titleText.implicitHeight + (subtitle.length ? 18 : 0) + 14 : 0)

    function requestGlow() {
        if (glowRequested || !manga || !manga.thumbnailUrl)
            return
        glowRequested = true
        ImageCache.accent(Api.coverKey(manga.thumbnailUrl, manga.thumbnailUrlLastFetched), c => {
            if (c) card.glow = Theme.vivid(c)
        })
    }
    onHotChanged: if (hot) requestGlow()

    // --- Entrance ------------------------------------------------------------
    opacity: enterDelay >= 0 ? 0 : 1
    transform: Translate { id: rise; y: card.enterDelay >= 0 ? 28 : 0 }
    Component.onCompleted: if (enterDelay >= 0) entrance.start()
    SequentialAnimation {
        id: entrance
        PauseAnimation { duration: Math.max(0, Math.min(card.enterDelay, 900)) }
        ParallelAnimation {
            NumberAnimation { target: card; property: "opacity"; to: 1; duration: Theme.slow; easing.type: Easing.OutCubic }
            NumberAnimation { target: rise; property: "y"; to: 0; duration: Theme.slower; easing.type: Easing.OutQuint }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPositionChanged: mouse => {
            card.px = Math.max(0, Math.min(1, mouse.x / width))
            card.py = Math.max(0, Math.min(1, mouse.y / lift.height))
        }
        onExited: { card.px = 0.5; card.py = 0.5 }
        onClicked: mouse => mouse.button === Qt.RightButton ? card.menu() : card.clicked()
    }

    Item {
        id: lift
        width: parent.width
        height: Math.round(width * 1.5)
        scale: hover.pressed ? 0.975 : card.hot ? 1.035 : 1
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

        transform: [
            Rotation {
                origin.x: lift.width / 2
                origin.y: lift.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: card.hot ? (0.5 - card.py) * 11 : 0
                Behavior on angle { SpringAnimation { spring: 3.2; damping: 0.3; epsilon: 0.05 } }
            },
            Rotation {
                origin.x: lift.width / 2
                origin.y: lift.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: card.hot ? (card.px - 0.5) * 14 : 0
                Behavior on angle { SpringAnimation { spring: 3.2; damping: 0.3; epsilon: 0.05 } }
            },
            Translate {
                y: card.hot ? -8 : 0
                Behavior on y { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutQuint } }
            }
        ]

        RectangularShadow {
            // Resting shadow deepens into a coloured glow on hover.
            anchors.fill: cover
            radius: Theme.radiusM
            offset.y: card.hot ? 24 : 10
            blur: card.hot ? 46 : 22
            spread: card.hot ? -2 : -6
            color: card.hot ? Theme.alpha(card.glow, 0.42) : Qt.rgba(0, 0, 0, 0.55)
            Behavior on offset.y { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutQuint } }
            Behavior on blur { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutQuint } }
            Behavior on color { ColorAnimation { duration: Theme.slow } }
        }

        Cover {
            id: cover
            anchors.fill: parent
            source: Api.mangaCover(card.manga)
        }

        Rectangle {
            // Bottom shade so badges and the progress bar read on any art.
            anchors.fill: parent
            radius: Theme.radiusM
            gradient: Gradient {
                GradientStop { position: 0.6; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
            }
        }

        Shape {
            // Specular glare that follows the pointer across the cover.
            anchors.fill: parent
            opacity: card.hot ? 1 : 0
            visible: opacity > 0
            preferredRendererType: Shape.CurveRenderer
            Behavior on opacity { NumberAnimation { duration: Theme.normal } }
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: card.px * lift.width
                    centerY: card.py * lift.height
                    centerRadius: lift.width * 0.95
                    focalX: centerX
                    focalY: centerY
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.24) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.05) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                }
                PathRectangle { x: 0; y: 0; width: lift.width; height: lift.height; radius: Theme.radiusM }
            }
        }

        Rectangle {
            // Edge light.
            anchors.fill: parent
            radius: Theme.radiusM
            color: "transparent"
            border.width: 1
            border.color: card.selected ? Theme.alpha(card.glow, 0.9)
                        : card.hot ? Theme.alpha(Qt.lighter(card.glow, 1.3), 0.55) : Theme.alpha("#FFFFFF", 0.08)
            Behavior on border.color { ColorAnimation { duration: Theme.normal } }
        }

        Rectangle {
            visible: !!card.manga && card.manga.unreadCount > 0
            anchors { left: parent.left; top: parent.top; margins: 8 }
            height: 22
            width: Math.max(22, unread.implicitWidth + 14)
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

        Rectangle {
            // Series progress, floating just above the bottom edge.
            visible: card.progress >= 0
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 9 }
            height: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.18)
            Rectangle {
                width: Math.max(height, parent.width * Math.min(1, card.progress))
                height: parent.height
                radius: 2
                color: card.progress >= 1 ? Theme.accent : Qt.lighter(card.glow, 1.15)
                Behavior on color { ColorAnimation { duration: Theme.slow } }
            }
        }

        Rectangle {
            // Resume straight from the grid.
            visible: card.playable
            anchors.centerIn: parent
            width: 54; height: 54; radius: 27
            color: Theme.alpha(Theme.ink, 0.55)
            border.color: Theme.alpha("#FFFFFF", 0.35)
            opacity: card.hot ? 1 : 0
            scale: card.hot ? (playHover.containsMouse ? 1.12 : 1) : 0.6
            Behavior on opacity { NumberAnimation { duration: Theme.normal } }
            Behavior on scale { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
            Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; glyph: Icons.play; size: 22; color: "#FFFFFF" }
            MouseArea {
                id: playHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: card.play()
            }
        }
    }

    Column {
        visible: card.showTitle
        anchors.top: lift.bottom
        anchors.topMargin: 12
        width: parent.width
        spacing: 3
        Text {
            id: titleText
            width: parent.width
            text: card.manga ? card.manga.title : ""
            maximumLineCount: 2
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            font.pixelSize: 14
            font.weight: Font.DemiBold
            lineHeight: 1.12
            color: card.hot ? Theme.text : Theme.alpha(Theme.text, 0.86)
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
        Text {
            width: parent.width
            visible: card.subtitle.length > 0
            text: card.subtitle
            elide: Text.ElideRight
            font.pixelSize: 12
            color: Theme.textFaint
        }
    }
}
