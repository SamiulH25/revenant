import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

Item {
    id: page

    property int mangaId
    property var seed
    property var manga: seed
    property var chapters: []
    property bool loading: true
    property bool refreshing: false
    property bool newestFirst: true
    property bool unreadOnly: false
    property bool descriptionOpen: false
    property color tint: Theme.accent

    readonly property var resume: chapters.length ? Api.resumeChapter(chapters) : null
    readonly property bool started: chapters.some(c => c.isRead || c.lastPageRead > 0)
    readonly property int readCount: chapters.filter(c => c.isRead).length

    readonly property var shownChapters: {
        let list = unreadOnly ? chapters.filter(c => !c.isRead) : chapters
        return newestFirst ? list : list.slice().reverse()
    }

    KeyedListModel { id: chapterModel }
    onShownChaptersChanged: chapterModel.sync(shownChapters)

    function statusLabel(status) {
        switch (status) {
        case "ONGOING": return qsTr("Ongoing")
        case "COMPLETED": return qsTr("Completed")
        case "LICENSED": return qsTr("Licensed")
        case "PUBLISHING_FINISHED": return qsTr("Publishing finished")
        case "CANCELLED": return qsTr("Cancelled")
        case "ON_HIATUS": return qsTr("On hiatus")
        default: return ""
        }
    }

    function formatDate(ms) {
        const t = Number(ms)
        if (!t)
            return ""
        const days = Math.floor((Date.now() - t) / 86400000)
        if (days < 1) return qsTr("Today")
        if (days < 2) return qsTr("Yesterday")
        if (days < 7) return qsTr("%1 days ago").arg(days)
        return new Date(t).toLocaleDateString(Qt.locale(), "MMM d, yyyy")
    }

    function apply(full) {
        requestTint(full)
        manga = full
        chapters = full.chapters ? full.chapters.nodes : []
        if (loading)
            Qt.callLater(list.positionViewAtBeginning) // the header grew; start at the top
        loading = false
    }

    function load() {
        Api.manga(mangaId, function (error, full) {
            if (error) {
                loading = false
                return app.toast(error, "error")
            }
            apply(full)
            if (!full.initialized || chapters.length === 0)
                refresh()
        })
    }

    function refresh() {
        refreshing = true
        Api.refreshManga(mangaId, function (error, full) {
            refreshing = false
            if (error)
                return app.toast(error, "error")
            apply(full)
        })
    }

    function toggleLibrary() {
        const next = !manga.inLibrary
        Api.setInLibrary(mangaId, next, function (error) {
            if (error)
                return app.toast(error, "error")
            manga = Object.assign({}, manga, { inLibrary: next })
            app.libraryRevision++
            app.toast(next ? qsTr("Added to library") : qsTr("Removed from library"))
        })
    }

    function setRead(ids, read) {
        Api.updateChapters(ids, { isRead: read }, function (error) {
            if (error)
                return app.toast(error, "error")
            const set = new Set(ids)
            chapters = chapters.map(c => set.has(c.id) ? Object.assign({}, c, { isRead: read, lastPageRead: read ? c.lastPageRead : 0 }) : c)
            app.libraryRevision++
        })
    }

    function markPreviousRead(chapter) {
        // Everything older than (and including) this chapter.
        const ids = chapters.filter(c => c.sourceOrder <= chapter.sourceOrder && !c.isRead).map(c => c.id)
        if (ids.length)
            setRead(ids, true)
    }

    // Unread chapters oldest first, skipping ones on disk or in the queue.
    function unreadToFetch() {
        return chapters.filter(c => !c.isRead && !c.isDownloaded && !app.downloadMap[c.id]).reverse()
    }

    function deleteDownloads(ids) {
        Api.deleteDownloads(ids, function (error) {
            if (error)
                return app.toast(error, "error")
            const set = new Set(ids)
            chapters = chapters.map(c => set.has(c.id) ? Object.assign({}, c, { isDownloaded: false }) : c)
        })
    }

    function read(chapter) {
        app.openReader(manga, chapter, chapters)
    }

    property bool tintRequested: false
    function requestTint(m) {
        if (tintRequested || !m || !m.thumbnailUrl)
            return
        tintRequested = true
        ImageCache.accent(Api.coverKey(m.thumbnailUrl, m.thumbnailUrlLastFetched), c => { if (c) page.tint = c })
    }

    Component.onCompleted: {
        requestTint(seed)
        load()
    }
    function quietReload() {
        Api.manga(page.mangaId, (error, full) => { if (!error) page.apply(full) })
    }

    Timer { id: settleReload; interval: 600; onTriggered: page.quietReload() }

    Connections {
        target: app
        // Returning from the reader: pick up read progress quietly.
        function onLibraryRevisionChanged() { page.quietReload() }
        function onDownloadsSettled(mangaId) { if (mangaId === page.mangaId) settleReload.restart() }
    }

    Ambient {
        anchors.left: parent.left
        anchors.right: parent.right
        height: 720
        y: Math.min(0, -list.contentY * 0.35 - list.originY * 0.35)
        source: page.manga ? Api.mangaCover(page.manga) : ""
        tint: page.tint
    }

    ListView {
        id: list
        anchors.fill: parent
        model: chapterModel
        // No current item: otherwise inserts keep row 0 pinned and the
        // header drifts off the top.
        currentIndex: -1
        highlightFollowsCurrentItem: false
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        cacheBuffer: 1000
        bottomMargin: 60

        header: Item {
            width: list.width
            height: heroCol.implicitHeight + 40

            ColumnLayout {
                id: heroCol
                x: Theme.gutter
                width: parent.width - Theme.gutter * 2
                spacing: 0

                Item { Layout.preferredHeight: 22 }
                IconButton { glyph: Icons.arrowLeft; tip: qsTr("Back"); filled: true; onClicked: app.back() }
                Item { Layout.preferredHeight: 18 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 40

                    Item {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 240
                        Layout.preferredHeight: 360

                        Glow {
                            // Coloured light spilling from behind the cover.
                            anchors.centerIn: parent
                            width: parent.width * 2.2
                            height: parent.height * 1.8
                            color: page.tint
                            strength: 0.22
                        }
                        Cover {
                            anchors.fill: parent
                            radius: Theme.radiusL
                            source: page.manga ? Api.mangaCover(page.manga) : ""
                            decodeWidth: 768
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusL
                            color: "transparent"
                            border.color: Theme.strokeStrong
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 12

                        Text {
                            Layout.topMargin: 6
                            text: [page.manga && page.manga.source ? page.manga.source.displayName : "",
                                   page.manga ? page.statusLabel(page.manga.status) : ""].filter(s => s).join("  ·  ").toUpperCase()
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 2
                            color: page.tint
                        }

                        Text {
                            Layout.fillWidth: true
                            text: page.manga ? page.manga.title : ""
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.family: Theme.display
                            font.pixelSize: text.length > 60 ? 38 : 50
                            font.weight: Font.Medium
                            font.letterSpacing: -1
                            lineHeight: 1.02
                            color: Theme.text
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: {
                                if (!page.manga) return ""
                                const a = page.manga.author, b = page.manga.artist
                                return a && b && a !== b ? a + "  ·  " + b : (a || b || "")
                            }
                            elide: Text.ElideRight
                            font.pixelSize: 14
                            color: Theme.textDim
                        }

                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 6
                            visible: !!(page.manga && page.manga.genre && page.manga.genre.length > 0)
                            Repeater {
                                model: page.manga && page.manga.genre ? page.manga.genre.slice(0, 12) : []
                                Rectangle {
                                    required property string modelData
                                    implicitWidth: g.implicitWidth + 20
                                    implicitHeight: 26
                                    radius: 13
                                    color: Theme.alpha(Theme.text, 0.05)
                                    border.color: Theme.stroke
                                    Text { id: g; anchors.centerIn: parent; text: modelData; font.pixelSize: 12; color: Theme.textDim }
                                }
                            }
                        }

                        RowLayout {
                            Layout.topMargin: 12
                            spacing: 10

                            PillButton {
                                implicitHeight: 46
                                primary: true
                                accent: page.tint
                                enabled: page.resume !== null
                                glyph: Icons.play
                                text: !page.resume ? qsTr("No chapters")
                                    : page.started ? qsTr("Continue · %1").arg(page.resume.name)
                                    : qsTr("Start reading")
                                onClicked: page.read(page.resume)
                            }
                            PillButton {
                                implicitHeight: 46
                                checked: !!(page.manga && page.manga.inLibrary)
                                accent: page.tint
                                glyph: checked ? Icons.bookMarked : Icons.plus
                                text: checked ? qsTr("In library") : qsTr("Add to library")
                                onClicked: page.toggleLibrary()
                            }
                            IconButton {
                                implicitWidth: 46; implicitHeight: 46
                                glyph: Icons.refreshCw
                                tip: qsTr("Refresh from source")
                                filled: true
                                enabled: !page.refreshing
                                RotationAnimator on rotation {
                                    running: page.refreshing
                                    from: 0; to: 360; duration: 900
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running) parent.rotation = 0
                                }
                                onClicked: page.refresh()
                            }
                            IconButton {
                                implicitWidth: 46; implicitHeight: 46
                                visible: !!(page.manga && page.manga.realUrl)
                                glyph: Icons.externalLink
                                tip: qsTr("Open on the web")
                                filled: true
                                onClicked: Qt.openUrlExternally(page.manga.realUrl)
                            }
                        }

                        Text {
                            id: desc
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            Layout.maximumWidth: 820
                            visible: text.length > 0
                            text: page.manga && page.manga.description ? page.manga.description.trim() : ""
                            wrapMode: Text.WordWrap
                            maximumLineCount: page.descriptionOpen ? 1000 : 4
                            elide: Text.ElideRight
                            font.pixelSize: 14
                            lineHeight: 1.4
                            color: Theme.textDim
                            textFormat: Text.PlainText
                        }
                        Text {
                            visible: desc.truncated || page.descriptionOpen
                            text: page.descriptionOpen ? qsTr("Show less") : qsTr("Read more")
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: page.tint
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.descriptionOpen = !page.descriptionOpen
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 44 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: qsTr("Chapters")
                        font.family: Theme.display
                        font.pixelSize: 24
                        font.weight: Font.Medium
                        color: Theme.text
                    }
                    Text {
                        Layout.alignment: Qt.AlignBaseline
                        text: page.chapters.length ? qsTr("%1 of %2 read").arg(page.readCount).arg(page.chapters.length) : ""
                        font.pixelSize: 13
                        font.features: { "tnum": 1 }
                        color: Theme.textFaint
                    }
                    Item { Layout.fillWidth: true }
                    Chip {
                        text: qsTr("Unread")
                        accent: page.tint
                        checked: page.unreadOnly
                        onToggled: page.unreadOnly = checked
                    }
                    IconButton {
                        glyph: page.newestFirst ? Icons.arrowDownWideNarrow : Icons.arrowUpNarrowWide
                        tip: page.newestFirst ? qsTr("Newest first") : qsTr("Oldest first")
                        onClicked: page.newestFirst = !page.newestFirst
                    }
                    IconButton {
                        glyph: Icons.download
                        tip: qsTr("Download")
                        onClicked: downloadMenu.popup()
                        PopMenu {
                            id: downloadMenu
                            Action { text: qsTr("Next 5 unread"); onTriggered: app.download(page.unreadToFetch().slice(0, 5).map(c => c.id)) }
                            Action { text: qsTr("Next 10 unread"); onTriggered: app.download(page.unreadToFetch().slice(0, 10).map(c => c.id)) }
                            Action { text: qsTr("All unread"); onTriggered: app.download(page.unreadToFetch().map(c => c.id)) }
                            Action {
                                text: qsTr("All chapters")
                                onTriggered: app.download(page.chapters.filter(c => !c.isDownloaded && !app.downloadMap[c.id]).reverse().map(c => c.id))
                            }
                            MenuSeparator { contentItem: Rectangle { implicitHeight: 1; color: Theme.stroke } }
                            Action {
                                text: qsTr("Delete downloaded chapters")
                                enabled: page.chapters.some(c => c.isDownloaded)
                                onTriggered: page.deleteDownloads(page.chapters.filter(c => c.isDownloaded).map(c => c.id))
                            }
                        }
                    }
                    IconButton {
                        glyph: Icons.bookOpenCheck
                        tip: qsTr("Mark all as read")
                        enabled: page.readCount < page.chapters.length
                        onClicked: page.setRead(page.chapters.filter(c => !c.isRead).map(c => c.id), true)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    Layout.preferredHeight: 1
                    color: Theme.stroke
                }

                // Progress across the whole series.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 2
                    Layout.topMargin: -1
                    color: "transparent"
                    visible: page.chapters.length > 0
                    Rectangle {
                        width: parent.width * (page.readCount / Math.max(1, page.chapters.length))
                        height: 2
                        color: page.tint
                        Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    visible: page.chapters.length === 0
                    Spinner { anchors.centerIn: parent; size: 24; visible: page.loading || page.refreshing }
                    Text {
                        anchors.centerIn: parent
                        visible: !page.loading && !page.refreshing
                        text: qsTr("No chapters found at this source.")
                        color: Theme.textDim
                    }
                }
            }
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property var ch: modelData
            readonly property bool isResume: page.resume && page.resume.id === ch.id

            // ListView positions delegates itself, so the gutter lives on
            // the children rather than on x.
            width: list.width
            height: 62

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.gutter - 12
                anchors.rightMargin: Theme.gutter - 12
                radius: Theme.radiusM
                color: row.isResume ? Theme.alpha(page.tint, 0.08) : rowMouse.containsMouse ? Theme.hover : "transparent"
                border.color: row.isResume ? Theme.alpha(page.tint, 0.25) : "transparent"
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                anchors.leftMargin: Theme.gutter - 12
                anchors.rightMargin: Theme.gutter - 12
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        menu.popup()
                    else
                        page.read(row.ch)
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.gutter + 2
                anchors.rightMargin: Theme.gutter - 4
                spacing: 14

                Rectangle {
                    // Read-state dot: filled tint = unread, hollow = read.
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    radius: 4
                    color: row.ch.isRead ? "transparent" : page.tint
                    border.color: row.ch.isRead ? Theme.textFaint : page.tint
                    opacity: row.ch.isRead ? 0.5 : 1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        text: row.ch.name
                        elide: Text.ElideRight
                        font.pixelSize: 14
                        font.weight: row.ch.isRead ? Font.Normal : Font.Medium
                        color: row.ch.isRead ? Theme.textFaint : Theme.text
                    }
                    Text {
                        Layout.fillWidth: true
                        text: {
                            const parts = []
                            if (row.ch.scanlator) parts.push(row.ch.scanlator)
                            const d = page.formatDate(row.ch.uploadDate)
                            if (d) parts.push(d)
                            if (!row.ch.isRead && row.ch.lastPageRead > 0)
                                parts.push(qsTr("Page %1").arg(row.ch.lastPageRead + 1) + (row.ch.pageCount > 0 ? qsTr(" of %1").arg(row.ch.pageCount) : ""))
                            return parts.join("  ·  ")
                        }
                        elide: Text.ElideRight
                        font.pixelSize: 12
                        color: Theme.textFaint
                    }
                }

                Icon {
                    visible: row.ch.isBookmarked
                    glyph: Icons.bookmark
                    size: 15
                    color: page.tint
                }

                // Download state: progress while queued, a mark once on disk.
                Row {
                    readonly property var queued: app.downloadMap[row.ch.id]
                    visible: !!queued
                    spacing: 6
                    Spinner { size: 14; color: page.tint; anchors.verticalCenter: parent.verticalCenter; running: !!parent.queued && parent.queued.state === "DOWNLOADING" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.queued ? (parent.queued.state === "DOWNLOADING" ? Math.round(parent.queued.progress * 100) + "%" : qsTr("Queued")) : ""
                        font.pixelSize: 11
                        font.features: { "tnum": 1 }
                        color: Theme.textDim
                    }
                }
                IconButton {
                    readonly property bool onDisk: row.ch.isDownloaded
                    visible: !app.downloadMap[row.ch.id] && (onDisk || rowMouse.containsMouse || hovered)
                    glyph: onDisk ? (hovered ? Icons.trash2 : Icons.circleCheck) : Icons.download
                    tip: onDisk ? qsTr("Delete download") : qsTr("Download")
                    iconSize: 16
                    tint: onDisk ? page.tint : Theme.textDim
                    onClicked: onDisk ? page.deleteDownloads([row.ch.id]) : app.download([row.ch.id])
                }

                IconButton {
                    opacity: rowMouse.containsMouse || hovered ? 1 : 0
                    glyph: row.ch.isRead ? Icons.eyeOff : Icons.eye
                    tip: row.ch.isRead ? qsTr("Mark unread") : qsTr("Mark read")
                    iconSize: 16
                    tint: Theme.textDim
                    onClicked: page.setRead([row.ch.id], !row.ch.isRead)
                }
                IconButton {
                    opacity: rowMouse.containsMouse || hovered ? 1 : 0
                    glyph: Icons.ellipsisVertical
                    iconSize: 16
                    tint: Theme.textDim
                    onClicked: menu.popup()
                }
            }

            PopMenu {
                id: menu
                Action { text: row.ch.isRead ? qsTr("Mark as unread") : qsTr("Mark as read"); onTriggered: page.setRead([row.ch.id], !row.ch.isRead) }
                Action { text: qsTr("Mark previous as read"); onTriggered: page.markPreviousRead(row.ch) }
                Action {
                    text: row.ch.isBookmarked ? qsTr("Remove bookmark") : qsTr("Bookmark")
                    onTriggered: Api.updateChapters([row.ch.id], { isBookmarked: !row.ch.isBookmarked }, error => {
                        if (!error) page.chapters = page.chapters.map(c => c.id === row.ch.id ? Object.assign({}, c, { isBookmarked: !c.isBookmarked }) : c)
                    })
                }
                Action {
                    text: row.ch.isDownloaded ? qsTr("Delete download") : qsTr("Download")
                    enabled: !app.downloadMap[row.ch.id]
                    onTriggered: row.ch.isDownloaded ? page.deleteDownloads([row.ch.id]) : app.download([row.ch.id])
                }
            }
        }
    }
}
