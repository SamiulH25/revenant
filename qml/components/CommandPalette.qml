import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import Revenant

// Ctrl+K: one box that finds titles in the library, jumps to sources and
// pages, runs actions, and hands anything else to a search of every source.
Popup {
    id: palette

    property var library: []
    property var sources: []
    property string query: ""
    property var results: []
    property int current: 0

    signal searchEverywhere(string text)
    signal openSourceRequested(var source)
    signal updateLibraryRequested()

    parent: Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.max(60, Math.round(parent.height * 0.12))
    width: Math.min(720, parent.width - 80)
    height: Math.min(frame.implicitHeight, parent.height - y - 60)
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    readonly property var actions: [
        { label: qsTr("Library"), hint: "Ctrl+1", glyph: Icons.libraryBig, run: () => app.goTab("library") },
        { label: qsTr("Discover"), hint: "Ctrl+2", glyph: Icons.compass, run: () => app.goTab("browse") },
        { label: qsTr("History"), hint: "Ctrl+3", glyph: Icons.history, run: () => app.goTab("history") },
        { label: qsTr("Downloads"), hint: "Ctrl+4", glyph: Icons.download, run: () => app.goTab("downloads") },
        { label: qsTr("Extensions"), hint: "Ctrl+5", glyph: Icons.puzzle, run: () => app.goTab("extensions") },
        { label: qsTr("Settings"), hint: "Ctrl+,", glyph: Icons.settings, run: () => app.goTab("settings") },
        { label: qsTr("Update library"), hint: "Ctrl+R", glyph: Icons.refreshCw, run: () => palette.updateLibraryRequested() },
        { label: qsTr("Surprise me"), hint: "", glyph: Icons.dices, run: () => palette.surprise() },
        { label: qsTr("Toggle fullscreen"), hint: "F11", glyph: Icons.maximize, run: () => app.visibility = app.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }
    ]

    function openWith(text) {
        query = text || ""
        field.text = query
        open()
        Api.library((e, list) => { if (!e) { palette.library = list; palette.rebuild() } })
        Api.sources((e, list) => { if (!e) { palette.sources = list; palette.rebuild() } })
        rebuild()
    }

    function surprise() {
        const unread = library.filter(m => m.unreadCount > 0)
        const pool = unread.length ? unread : library
        if (pool.length)
            app.openManga(pool[Math.floor(Math.random() * pool.length)])
    }

    // 0 = no match. Prefix beats word-start beats substring beats subsequence.
    function score(q, text) {
        const s = (text || "").toLowerCase()
        if (!q) return 1
        if (s.startsWith(q)) return 100 - Math.min(40, s.length - q.length)
        const words = s.split(/[\s\-:&·]+/)
        if (words.some(w => w.startsWith(q))) return 80
        const at = s.indexOf(q)
        if (at >= 0) return 60 - Math.min(30, at)
        let i = 0
        for (const ch of s) if (ch === q[i]) i++
        return i === q.length ? 20 : 0
    }

    function rebuild() {
        const q = query.trim().toLowerCase()
        const out = []
        if (q) {
            out.push({ kind: "search", label: query.trim() })
            const titles = library.map(m => ({ m, s: score(q, m.title) })).filter(x => x.s > 0)
                .sort((a, b) => b.s - a.s).slice(0, 6)
            if (titles.length) {
                out.push({ kind: "header", label: qsTr("In your library") })
                titles.forEach(x => out.push({ kind: "manga", manga: x.m }))
            }
            const srcs = sources.map(s => ({ src: s, s: score(q, s.displayName) })).filter(x => x.s > 0)
                .sort((a, b) => b.s - a.s).slice(0, 4)
            if (srcs.length) {
                out.push({ kind: "header", label: qsTr("Sources") })
                srcs.forEach(x => out.push({ kind: "source", source: x.src }))
            }
            const acts = actions.filter(a => score(q, a.label) > 0)
            if (acts.length) {
                out.push({ kind: "header", label: qsTr("Go to") })
                acts.forEach(a => out.push({ kind: "action", action: a }))
            }
        } else {
            const recent = library.filter(m => m.lastReadChapter && Number(m.lastReadChapter.lastReadAt) > 0)
                .sort((a, b) => Number(b.lastReadChapter.lastReadAt) - Number(a.lastReadChapter.lastReadAt)).slice(0, 4)
            if (recent.length) {
                out.push({ kind: "header", label: qsTr("Jump back in") })
                recent.forEach(m => out.push({ kind: "manga", manga: m }))
            }
            out.push({ kind: "header", label: qsTr("Go to") })
            actions.forEach(a => out.push({ kind: "action", action: a }))
        }
        results = out
        current = out.findIndex(r => r.kind !== "header")
        // A new model resets the view's index; put the highlight back.
        Qt.callLater(() => { list.currentIndex = palette.current; list.positionViewAtBeginning() })
    }
    onCurrentChanged: list.currentIndex = current

    function move(step) {
        let i = current
        for (let n = 0; n < results.length; ++n) {
            i = (i + step + results.length) % results.length
            if (results[i].kind !== "header") {
                current = i
                list.positionViewAtIndex(i, ListView.Contain)
                return
            }
        }
    }

    function activate(index) {
        const r = results[index]
        if (!r || r.kind === "header")
            return
        close()
        switch (r.kind) {
        case "search": searchEverywhere(r.label); break
        case "manga": app.openManga(r.manga); break
        case "source": openSourceRequested(r.source); break
        case "action": r.action.run(); break
        }
    }

    // The app behind blurs itself while the palette is open (see Main.qml).
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.3) }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: Theme.slow; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.fast }
            NumberAnimation { property: "scale"; to: 0.97; duration: Theme.fast }
        }
    }

    background: Item {
        RectangularShadow {
            anchors.fill: parent
            radius: Theme.radiusXL
            blur: 60
            offset.y: 30
            color: Qt.rgba(0, 0, 0, 0.7)
        }
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusXL
            color: Theme.alpha(Theme.raised, 0.94)
            border.color: Theme.glassEdge
        }
        Glow {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -height / 2
            width: parent.width * 1.1
            height: 160
            strength: 0.12
        }
    }

    contentItem: ColumnLayout {
        id: frame
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 68
            Layout.leftMargin: 24
            Layout.rightMargin: 18
            spacing: 14
            Icon { glyph: Icons.search; size: 20; color: Theme.accent }
            TextField {
                id: field
                Layout.fillWidth: true
                background: null
                padding: 0
                color: Theme.text
                font.pixelSize: 20
                placeholderText: qsTr("Search your library, sources, or anything…")
                placeholderTextColor: Theme.textFaint
                selectionColor: Theme.alpha(Theme.accent, 0.35)
                focus: true
                onTextChanged: { palette.query = text; palette.rebuild() }
                Keys.onUpPressed: palette.move(-1)
                Keys.onDownPressed: palette.move(1)
                Keys.onTabPressed: palette.move(1)
                Keys.onReturnPressed: palette.activate(palette.current)
                Keys.onEnterPressed: palette.activate(palette.current)
            }
            Rectangle {
                width: escText.implicitWidth + 14
                height: 24
                radius: 6
                color: Theme.alpha("#FFFFFF", 0.06)
                border.color: Theme.stroke
                Text { id: escText; anchors.centerIn: parent; text: "esc"; font.pixelSize: 11; font.weight: Font.DemiBold; color: Theme.textFaint }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.stroke }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight + 16, 460)
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            clip: true
            model: palette.results
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 120
            highlightFollowsCurrentItem: true
            highlight: Item {
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    radius: Theme.radiusM
                    color: Theme.alpha(Theme.accent, 0.11)
                    border.color: Theme.alpha(Theme.accent, 0.3)
                }
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool header: modelData.kind === "header"
                width: list.width
                height: header ? 34 : modelData.kind === "manga" ? 60 : 46
                opacity: 0
                Component.onCompleted: fadeIn.start()
                NumberAnimation { id: fadeIn; target: row; property: "opacity"; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }

                MouseArea {
                    anchors.fill: parent
                    enabled: !row.header
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: palette.current = row.index
                    onClicked: palette.activate(row.index)
                }

                Text {
                    visible: row.header
                    anchors.left: parent.left
                    anchors.leftMargin: 26
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    text: row.header ? row.modelData.label.toUpperCase() : ""
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.8
                    color: Theme.textFaint
                }

                RowLayout {
                    visible: !row.header
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    spacing: 14

                    Item {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: row.modelData.kind === "manga" ? 46 : 32
                        Cover {
                            anchors.fill: parent
                            visible: row.modelData.kind === "manga" || row.modelData.kind === "source"
                            radius: row.modelData.kind === "manga" ? 5 : 8
                            source: row.modelData.kind === "manga" ? Api.mangaCover(row.modelData.manga)
                                  : row.modelData.kind === "source" ? Api.cover(row.modelData.source.iconUrl) : ""
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: row.modelData.kind === "search" || row.modelData.kind === "action"
                            radius: 9
                            color: row.modelData.kind === "search" ? Theme.alpha(Theme.accent, 0.16) : Theme.alpha("#FFFFFF", 0.05)
                            Icon {
                                anchors.centerIn: parent
                                glyph: row.modelData.kind === "search" ? Icons.telescope
                                     : row.modelData.kind === "action" ? row.modelData.action.glyph : ""
                                size: 16
                                color: row.modelData.kind === "search" ? Theme.accent : Theme.textDim
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            color: row.index === palette.current ? Theme.text : Theme.alpha(Theme.text, 0.88)
                            textFormat: Text.StyledText
                            text: {
                                const r = row.modelData
                                if (r.kind === "search") return qsTr("Search every source for “%1”").arg(r.label)
                                if (r.kind === "manga") return r.manga.title
                                if (r.kind === "source") return r.source.displayName
                                if (r.kind === "action") return r.action.label
                                return ""
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            color: Theme.textFaint
                            text: {
                                const r = row.modelData
                                if (r.kind === "manga") {
                                    const parts = []
                                    if (r.manga.source) parts.push(r.manga.source.displayName)
                                    if (r.manga.unreadCount > 0) parts.push(qsTr("%1 unread").arg(r.manga.unreadCount))
                                    return parts.join("  ·  ")
                                }
                                if (r.kind === "source") return qsTr("Browse this source")
                                if (r.kind === "search") return qsTr("Results stream in from every installed source")
                                return ""
                            }
                        }
                    }

                    Text {
                        visible: text.length > 0
                        text: row.modelData.kind === "action" ? row.modelData.action.hint
                            : row.index === palette.current ? "↵" : ""
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.textFaint
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.stroke }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            spacing: 18
            Repeater {
                model: [["↑ ↓", qsTr("navigate")], ["↵", qsTr("open")], ["esc", qsTr("close")]]
                Row {
                    required property var modelData
                    spacing: 6
                    Text { text: modelData[0]; font.pixelSize: 12; font.weight: Font.Bold; color: Theme.textDim }
                    Text { text: modelData[1]; font.pixelSize: 12; color: Theme.textFaint }
                }
            }
            Item { Layout.fillWidth: true }
            Text { text: qsTr("Revenant"); font.family: Theme.display; font.italic: true; font.pixelSize: 13; color: Theme.textFaint }
        }
    }
}
