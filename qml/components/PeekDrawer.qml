import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import Revenant

// Quick look at a title without leaving the grid: slides in from the right
// with the synopsis, genres, newest chapters and the main actions. The
// arrow keys step through the titles it was opened from.
Item {
    id: drawer

    property Item backdrop
    property var manga: null
    property var chapters: []
    property var siblings: []
    property int index: -1
    property bool loading: false
    property bool opened: false
    property color tint: Theme.accent
    property int token: 0

    anchors.fill: parent
    visible: opened || panel.x < width
    enabled: opened

    function show(m, origin, list) {
        siblings = list || []
        index = siblings.findIndex(s => s.id === m.id)
        load(m)
        opened = true
        forceActiveFocus()
    }

    function close() {
        opened = false
    }

    function step(delta) {
        if (index < 0 || !siblings.length)
            return
        const next = index + delta
        if (next < 0 || next >= siblings.length)
            return
        index = next
        load(siblings[next])
    }

    function load(m) {
        manga = m
        chapters = []
        tint = Theme.accent
        loading = true
        const mine = ++token
        if (m.thumbnailUrl)
            ImageCache.accent(Api.coverKey(m.thumbnailUrl, m.thumbnailUrlLastFetched), c => { if (mine === token && c) drawer.tint = Theme.vivid(c) })
        Api.manga(m.id, (error, full) => {
            if (mine !== token)
                return
            if (!error && full.initialized && full.chapters.nodes.length) {
                apply(full)
                return
            }
            Api.refreshManga(m.id, (err, fresh) => {
                if (mine !== token)
                    return
                loading = false
                if (err)
                    return app.toast(err, "error")
                apply(fresh)
            })
        })
        cascade.restart()
    }

    function apply(full) {
        manga = Object.assign({}, manga, full)
        chapters = full.chapters ? full.chapters.nodes : []
        loading = false
    }

    function toggleLibrary() {
        const next = !manga.inLibrary
        Api.setInLibrary(manga.id, next, error => {
            if (error)
                return app.toast(error, "error")
            manga = Object.assign({}, manga, { inLibrary: next })
            app.libraryRevision++
            app.toast(next ? qsTr("Added to library") : qsTr("Removed from library"))
        })
    }

    Keys.onPressed: event => {
        switch (event.key) {
        case Qt.Key_Down: case Qt.Key_Right: case Qt.Key_J: step(1); break
        case Qt.Key_Up: case Qt.Key_Left: case Qt.Key_K: step(-1); break
        case Qt.Key_Escape: close(); break
        case Qt.Key_Return: case Qt.Key_Enter: if (manga) app.openManga(manga); break
        default: return
        }
        event.accepted = true
    }

    Rectangle {
        // Scrim: dims the page; clicking it closes the drawer.
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: drawer.opened ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent; onClicked: drawer.close() }
    }

    Item {
        id: panel
        width: Math.min(480, drawer.width * 0.5)
        height: parent.height - 24
        y: 12
        x: drawer.opened ? drawer.width - width - 12 : drawer.width + 40
        Behavior on x { NumberAnimation { duration: Theme.slower; easing.type: Easing.OutQuint } }
        onXChanged: glass.refresh()

        RectangularShadow {
            anchors.fill: parent
            radius: Theme.radiusXL
            blur: 60
            offset.x: -12
            color: Qt.rgba(0, 0, 0, 0.6)
        }

        GlassPanel {
            id: glass
            anchors.fill: parent
            radius: Theme.radiusXL
            backdrop: drawer.backdrop
            tint: Theme.alpha(Theme.surface, 0.86)
            blurMax: 64
        }

        Item {
            // Cover art bleeding into the top of the panel.
            anchors.fill: parent
            clip: true
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: panelMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Image {
                id: wash
                width: parent.width
                height: 360
                source: Api.mangaCover(drawer.manga)
                sourceSize.width: 200
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            MultiEffect {
                anchors.fill: wash
                source: wash
                blurEnabled: true
                blur: 1
                blurMax: 64
                saturation: 0.3
                opacity: wash.status === Image.Ready ? 0.55 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.slow } }
            }
            Rectangle {
                width: parent.width
                height: 362
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.alpha(Theme.surface, 0.1) }
                    GradientStop { position: 1; color: Theme.alpha(Theme.surface, 0.95) }
                }
            }
        }
        Item {
            id: panelMask
            anchors.fill: parent
            layer.enabled: true
            visible: false
            Rectangle { anchors.fill: parent; radius: Theme.radiusXL }
        }

        Flickable {
            id: scroller
            anchors.fill: parent
            anchors.margins: 1
            contentHeight: body.implicitHeight + 120
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            ColumnLayout {
                id: body
                x: 28
                y: 28
                width: scroller.width - 56
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: drawer.siblings.length > 1 && drawer.index >= 0 ? qsTr("%1 of %2").arg(drawer.index + 1).arg(drawer.siblings.length) : ""
                        font.pixelSize: 12
                        font.features: { "tnum": 1 }
                        color: Theme.textFaint
                    }
                    IconButton { glyph: Icons.chevronUp; tip: qsTr("Previous (↑)"); visible: drawer.siblings.length > 1; enabled: drawer.index > 0; onClicked: drawer.step(-1) }
                    IconButton { glyph: Icons.chevronDown; tip: qsTr("Next (↓)"); visible: drawer.siblings.length > 1; enabled: drawer.index < drawer.siblings.length - 1; onClicked: drawer.step(1) }
                    IconButton { glyph: Icons.x; tip: qsTr("Close (Esc)"); filled: true; onClicked: drawer.close() }
                }

                Item {
                    id: coverBox
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 6
                    Layout.preferredWidth: 190
                    Layout.preferredHeight: 285
                    Glow { anchors.centerIn: parent; width: parent.width * 2.4; height: parent.height * 1.6; color: drawer.tint; strength: 0.3 }
                    RectangularShadow {
                        anchors.fill: peekCover
                        radius: Theme.radiusL
                        blur: 40
                        offset.y: 20
                        color: Qt.rgba(0, 0, 0, 0.6)
                    }
                    Cover {
                        id: peekCover
                        anchors.fill: parent
                        radius: Theme.radiusL
                        decodeWidth: 400
                        source: Api.mangaCover(drawer.manga)
                    }
                }

                Text {
                    id: titleText
                    Layout.fillWidth: true
                    Layout.topMargin: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: drawer.manga ? drawer.manga.title : ""
                    wrapMode: Text.WordWrap
                    font.family: Theme.display
                    font.pixelSize: 30
                    font.weight: Font.Medium
                    font.letterSpacing: -0.5
                    lineHeight: 1.05
                    color: Theme.text
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    horizontalAlignment: Text.AlignHCenter
                    visible: text.length > 0
                    text: drawer.manga ? [drawer.manga.author, drawer.manga.source ? drawer.manga.source.displayName : ""].filter(s => s).join("  ·  ") : ""
                    elide: Text.ElideRight
                    font.pixelSize: 13
                    color: Theme.textDim
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    spacing: 6
                    visible: !!(drawer.manga && drawer.manga.genre && drawer.manga.genre.length)
                    Repeater {
                        model: drawer.manga && drawer.manga.genre ? drawer.manga.genre.slice(0, 8) : []
                        Rectangle {
                            required property string modelData
                            implicitWidth: g.implicitWidth + 20
                            implicitHeight: 26
                            radius: 13
                            color: Theme.alpha(drawer.tint, 0.1)
                            border.color: Theme.alpha(drawer.tint, 0.28)
                            Text { id: g; anchors.centerIn: parent; text: modelData; font.pixelSize: 12; color: Theme.alpha(Theme.text, 0.85) }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 22
                    spacing: 10
                    PillButton {
                        Layout.fillWidth: true
                        implicitHeight: 46
                        primary: true
                        accent: drawer.tint
                        glyph: Icons.play
                        enabled: drawer.chapters.length > 0
                        busy: drawer.loading
                        text: drawer.chapters.some(c => c.isRead || c.lastPageRead > 0) ? qsTr("Continue") : qsTr("Read now")
                        onClicked: {
                            const ch = Api.resumeChapter(drawer.chapters)
                            if (ch) app.openReader(drawer.manga, ch, drawer.chapters)
                        }
                    }
                    PillButton {
                        implicitHeight: 46
                        accent: drawer.tint
                        checked: !!(drawer.manga && drawer.manga.inLibrary)
                        glyph: checked ? Icons.bookMarked : Icons.plus
                        text: checked ? qsTr("Saved") : qsTr("Save")
                        onClicked: drawer.toggleLibrary()
                    }
                    IconButton {
                        implicitWidth: 46; implicitHeight: 46
                        filled: true
                        glyph: Icons.arrowUpRight
                        tip: qsTr("Open details (Enter)")
                        onClicked: app.openManga(drawer.manga)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 22
                    visible: text.length > 0
                    text: drawer.manga && drawer.manga.description ? drawer.manga.description.trim() : ""
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    font.pixelSize: 14
                    lineHeight: 1.45
                    color: Theme.textDim
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    visible: drawer.loading && !(drawer.manga && drawer.manga.description)
                    Spinner { anchors.centerIn: parent; size: 22; color: drawer.tint }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 26
                    visible: drawer.chapters.length > 0
                    Text {
                        text: qsTr("Chapters")
                        font.family: Theme.display
                        font.pixelSize: 19
                        color: Theme.text
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: Api.count(drawer.chapters.length, qsTr("%1 chapter"), qsTr("%1 chapters"))
                        font.pixelSize: 12
                        color: Theme.textFaint
                    }
                }

                Repeater {
                    model: drawer.chapters.slice(0, 6)
                    delegate: AbstractButton {
                        id: chRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.topMargin: index === 0 ? 10 : 2
                        implicitHeight: 44
                        hoverEnabled: true
                        onClicked: app.openReader(drawer.manga, modelData, drawer.chapters)
                        background: Rectangle {
                            radius: Theme.radiusM
                            color: chRow.hovered ? Theme.hover : "transparent"
                        }
                        contentItem: RowLayout {
                            spacing: 12
                            Rectangle {
                                Layout.leftMargin: 10
                                width: 6; height: 6; radius: 3
                                color: chRow.modelData.isRead ? "transparent" : drawer.tint
                                border.color: chRow.modelData.isRead ? Theme.textFaint : drawer.tint
                            }
                            Text {
                                Layout.fillWidth: true
                                text: chRow.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: 14
                                color: chRow.modelData.isRead ? Theme.textFaint : Theme.text
                            }
                            Icon {
                                Layout.rightMargin: 10
                                glyph: Icons.play
                                size: 13
                                color: drawer.tint
                                opacity: chRow.hovered ? 1 : 0
                            }
                        }
                    }
                }
            }
        }

        // Content cascade whenever a new title loads.
        SequentialAnimation {
            id: cascade
            ParallelAnimation {
                NumberAnimation { target: body; property: "opacity"; from: 0.2; to: 1; duration: Theme.slow; easing.type: Easing.OutCubic }
                NumberAnimation { target: body; property: "y"; from: 46; to: 28; duration: Theme.slower; easing.type: Easing.OutQuint }
                NumberAnimation { target: coverBox; property: "scale"; from: 0.9; to: 1; duration: Theme.slower; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            }
        }
    }
}
