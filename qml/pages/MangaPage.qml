import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
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
    // Cover flight: the card this page was opened from, and whether a
    // cover is in the air towards our hero.
    property Item origin
    property bool flying: false
    property bool landed: !flying
    // Rows rise in only while the page is fresh.
    property real openedAt: Date.now()
    // Items inside the list header, which page-level code can't name.
    property Item heroItem
    property var libraryPulse

    readonly property bool scrolled: list.contentY - list.originY > 60
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

    function chapterLabel(ch) {
        const n = Number(ch.chapterNumber)
        if (!(n > 0))
            return "·"
        return Number.isInteger(n) ? String(n) : n.toFixed(1)
    }

    function apply(full) {
        requestTint(full)
        manga = full
        chapters = full.chapters ? full.chapters.nodes : []
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
            if (next) {
                if (libraryPulse) libraryPulse.restart()
                // With categories set up, ask where it goes.
                Api.categories((err, list) => { if (!err && list.some(c => c.id !== 0)) app.editMangaCategories(manga) })
            }
        })
    }

    function setRead(ids, read) {
        Api.updateChapters(ids, { isRead: read }, function (error) {
            if (error)
                return app.toast(error, "error")
            const set = new Set(ids)
            chapters = chapters.map(c => set.has(c.id) ? Object.assign({}, c, { isRead: read, lastPageRead: read ? c.lastPageRead : 0 }) : c)
            app.libraryRevision++
            if (read)
                Api.trackProgress(mangaId)
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
        ImageCache.accent(Api.coverKey(m.thumbnailUrl, m.thumbnailUrlLastFetched), c => { if (c) page.tint = Theme.vivid(c) })
    }
    onTintChanged: if (StackView.status === StackView.Active) app.tint = tint
    StackView.onActivated: app.tint = tint

    // --- Cover flight ---------------------------------------------------------

    function heroRect() {
        if (!heroItem)
            return Qt.rect(Theme.gutter, Theme.contentTop + 70, 300, 450)
        return heroItem.mapToItem(page, 0, 0, heroItem.width, heroItem.height)
    }

    function landFlight() {
        if (!flying)
            return
        app.flight.land(heroRect(), Theme.radiusL)
    }

    // Flies the cover back onto the card it came from, if that's still there.
    function flyBack() {
        if (!origin || !manga || list.contentY - list.originY > 300)
            return
        let r = origin.mapToItem(app.contentItem, 0, 0, origin.width, origin.height)
        // The page underneath is mid-transition at a slight scale; aim for
        // where the card will be once it settles.
        for (let p = origin.parent; p; p = p.parent) {
            if (Math.abs(p.scale - 1) > 0.001 && p.scale > 0) {
                const c = p.mapToItem(app.contentItem, p.width / 2, p.height / 2)
                r = Qt.rect(c.x + (r.x - c.x) / p.scale, c.y + (r.y - c.y) / p.scale, r.width / p.scale, r.height / p.scale)
                break
            }
        }
        landed = false
        app.flight.fly(Api.mangaCover(manga), heroRect(), r, Theme.radiusL, Theme.radiusM)
    }

    Connections {
        target: app.flight
        enabled: page.flying
        function onLanded() {
            page.flying = false
            page.landed = true
        }
    }

    Component.onCompleted: {
        requestTint(seed)
        load()
        if (flying)
            Qt.callLater(() => Qt.callLater(page.landFlight))
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

    Backdrop {
        anchors.left: parent.left
        anchors.right: parent.right
        height: 860
        y: Math.min(0, -(list.contentY - list.originY) * 0.4)
        source: page.manga ? Api.mangaCover(page.manga) : ""
        tint: page.tint
        intensity: 0.75
        fadeStart: 0.4
    }

    ListView {
        id: list
        anchors.fill: parent
        model: chapterModel
        // No current item: otherwise inserts keep row 0 pinned and the
        // header drifts off the top.
        currentIndex: -1
        highlightFollowsCurrentItem: false
        // The hero header keeps growing as details and text layout arrive;
        // stay pinned to the top until the reader scrolls on their own.
        property bool touched: false
        onMovementStarted: touched = true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        cacheBuffer: 1000
        bottomMargin: 80

        header: Item {
            width: list.width
            height: heroCol.implicitHeight + Theme.contentTop + 20
            onHeightChanged: if (!list.touched) Qt.callLater(list.positionViewAtBeginning)

            ColumnLayout {
                id: heroCol
                x: Theme.gutter
                y: Theme.contentTop - 8
                width: parent.width - Theme.gutter * 2
                spacing: 0

                RowLayout {
                    spacing: 10
                    IconButton {
                        glyph: Icons.arrowLeft
                        tip: qsTr("Back")
                        filled: true
                        onClicked: app.back()
                    }
                    Text {
                        text: qsTr("Back")
                        font.pixelSize: 13
                        color: Theme.textDim
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: app.back() }
                    }
                }

                Item { Layout.preferredHeight: 22 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 52

                    Item {
                        id: coverBox
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 300
                        Layout.preferredHeight: 450

                        Glow {
                            // Coloured light spilling from behind the cover.
                            anchors.centerIn: parent
                            width: parent.width * 2.6
                            height: parent.height * 1.9
                            color: page.tint
                            strength: page.landed ? 0.34 : 0
                            Behavior on strength { NumberAnimation { duration: Theme.slower } }
                            Behavior on color { ColorAnimation { duration: Theme.slow } }
                        }
                        RectangularShadow {
                            anchors.fill: heroCover
                            radius: Theme.radiusL
                            blur: 50
                            offset.y: 28
                            color: Qt.rgba(0, 0, 0, 0.6)
                            opacity: heroCover.opacity
                        }
                        Cover {
                            id: heroCover
                            anchors.fill: parent
                            radius: Theme.radiusL
                            source: page.manga ? Api.mangaCover(page.manga) : ""
                            decodeWidth: 768
                            opacity: page.landed ? 1 : 0
                            Component.onCompleted: page.heroItem = heroCover
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusL
                            color: "transparent"
                            border.color: Theme.alpha("#FFFFFF", 0.12)
                            opacity: heroCover.opacity
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 0

                        Text {
                            Layout.topMargin: 10
                            transform: Reveal { id: r1; delay: 60 }
                            opacity: r1.progress
                            text: [page.manga && page.manga.source ? page.manga.source.displayName : "",
                                   page.manga ? page.statusLabel(page.manga.status) : ""].filter(s => s).join("  ·  ").toUpperCase()
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.letterSpacing: 2.2
                            color: Qt.lighter(page.tint, 1.15)
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            transform: Reveal { id: r2; delay: 110; distance: 30 }
                            opacity: r2.progress
                            text: page.manga ? page.manga.title : ""
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.family: Theme.display
                            font.pixelSize: text.length > 40 ? 46 : text.length > 20 ? 58 : 72
                            font.weight: Font.Medium
                            font.letterSpacing: -1.6
                            lineHeight: 0.98
                            color: Theme.text
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            transform: Reveal { id: r3; delay: 160 }
                            opacity: r3.progress
                            visible: text.length > 0
                            text: {
                                if (!page.manga) return ""
                                const a = page.manga.author, b = page.manga.artist
                                return a && b && a !== b ? qsTr("by %1 and %2").arg(a).arg(b) : (a || b ? qsTr("by %1").arg(a || b) : "")
                            }
                            elide: Text.ElideRight
                            font.pixelSize: 15
                            color: Theme.textDim
                        }

                        // Stat pills.
                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: 20
                            spacing: 8
                            transform: Reveal { id: r4; delay: 210 }
                            opacity: r4.progress
                            Repeater {
                                model: {
                                    const out = []
                                    if (page.chapters.length) {
                                        out.push({ glyph: Icons.bookCopy, text: Api.count(page.chapters.length, qsTr("%1 chapter"), qsTr("%1 chapters")) })
                                        const pct = Math.round(page.readCount / page.chapters.length * 100)
                                        out.push({ glyph: Icons.bookOpenCheck, text: pct >= 100 ? qsTr("Finished") : qsTr("%1% read").arg(pct), hot: pct > 0 })
                                        const newest = page.chapters.reduce((m, c) => Math.max(m, Number(c.uploadDate) || 0), 0)
                                        if (newest) out.push({ glyph: Icons.clock, text: qsTr("Updated %1").arg(page.formatDate(newest).toLowerCase()) })
                                        const dl = page.chapters.filter(c => c.isDownloaded).length
                                        if (dl) out.push({ glyph: Icons.download, text: qsTr("%1 offline").arg(dl) })
                                    }
                                    return out
                                }
                                delegate: Rectangle {
                                    required property var modelData
                                    implicitHeight: 32
                                    implicitWidth: statRow.implicitWidth + 24
                                    radius: 16
                                    color: modelData.hot ? Theme.alpha(page.tint, 0.14) : Theme.alpha("#FFFFFF", 0.05)
                                    border.color: modelData.hot ? Theme.alpha(page.tint, 0.35) : Theme.stroke
                                    Row {
                                        id: statRow
                                        anchors.centerIn: parent
                                        spacing: 7
                                        Icon { anchors.verticalCenter: parent.verticalCenter; glyph: modelData.glyph; size: 14; color: modelData.hot ? page.tint : Theme.textDim }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.text; font.pixelSize: 13; font.weight: Font.Medium; color: Theme.alpha(Theme.text, 0.9) }
                                    }
                                }
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            spacing: 6
                            transform: Reveal { id: r5; delay: 250 }
                            opacity: r5.progress
                            visible: !!(page.manga && page.manga.genre && page.manga.genre.length > 0)
                            Repeater {
                                model: page.manga && page.manga.genre ? page.manga.genre.slice(0, 12) : []
                                Rectangle {
                                    required property string modelData
                                    implicitWidth: g.implicitWidth + 22
                                    implicitHeight: 28
                                    radius: 14
                                    color: "transparent"
                                    border.color: Theme.strokeStrong
                                    Text { id: g; anchors.centerIn: parent; text: modelData; font.pixelSize: 12; color: Theme.textDim }
                                }
                            }
                        }

                        RowLayout {
                            Layout.topMargin: 26
                            spacing: 10
                            transform: Reveal { id: r6; delay: 300 }
                            opacity: r6.progress

                            PillButton {
                                implicitHeight: 52
                                primary: true
                                accent: page.tint
                                enabled: page.resume !== null
                                glyph: Icons.play
                                text: !page.resume ? (page.loading || page.refreshing ? qsTr("Loading chapters…") : qsTr("No chapters"))
                                    : page.started ? qsTr("Continue · %1").arg(page.resume.name)
                                    : qsTr("Start reading")
                                onClicked: page.read(page.resume)
                            }
                            PillButton {
                                id: libraryButton
                                implicitHeight: 52
                                checked: !!(page.manga && page.manga.inLibrary)
                                accent: page.tint
                                glyph: checked ? Icons.bookMarked : Icons.plus
                                text: checked ? qsTr("In library") : qsTr("Add to library")
                                onClicked: page.toggleLibrary()
                                Component.onCompleted: page.libraryPulse = pulseAnim
                                SequentialAnimation {
                                    id: pulseAnim
                                    NumberAnimation { target: libraryButton; property: "scale"; to: 1.12; duration: 120; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: libraryButton; property: "scale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 3 }
                                }
                            }
                            IconButton {
                                implicitWidth: 52; implicitHeight: 52
                                visible: !!(page.manga && page.manga.inLibrary)
                                glyph: Icons.tag
                                tip: qsTr("Categories")
                                filled: true
                                onClicked: app.editMangaCategories(page.manga)
                            }
                            IconButton {
                                implicitWidth: 52; implicitHeight: 52
                                glyph: Icons.link
                                tip: qsTr("Tracking")
                                filled: true
                                onClicked: app.openTracking(page.manga)
                            }
                            IconButton {
                                implicitWidth: 52; implicitHeight: 52
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
                                implicitWidth: 52; implicitHeight: 52
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
                            Layout.topMargin: 24
                            Layout.maximumWidth: 760
                            transform: Reveal { id: r7; delay: 350 }
                            opacity: r7.progress
                            visible: text.length > 0
                            text: page.manga && page.manga.description ? page.manga.description.trim() : ""
                            wrapMode: Text.WordWrap
                            maximumLineCount: page.descriptionOpen ? 1000 : 4
                            elide: Text.ElideRight
                            font.pixelSize: 15
                            lineHeight: 1.5
                            color: Theme.textDim
                            textFormat: Text.PlainText
                        }
                        Text {
                            Layout.topMargin: 6
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

                Item { Layout.preferredHeight: 56 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: qsTr("Chapters")
                        font.family: Theme.display
                        font.pixelSize: 30
                        font.weight: Font.Medium
                        font.letterSpacing: -0.5
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
                        implicitHeight: 36
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

                // Progress across the whole series, drawn as a lit track.
                Item {
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    Layout.preferredHeight: 4
                    Layout.bottomMargin: 10
                    Rectangle { anchors.fill: parent; radius: 2; color: Theme.alpha("#FFFFFF", 0.07) }
                    Rectangle {
                        height: parent.height
                        radius: 2
                        width: parent.width * (page.readCount / Math.max(1, page.chapters.length))
                        color: page.tint
                        Behavior on width { NumberAnimation { duration: Theme.slower; easing.type: Easing.OutQuint } }
                        RectangularShadow { anchors.fill: parent; blur: 12; color: Theme.alpha(page.tint, 0.6) }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    visible: page.chapters.length === 0
                    Spinner { anchors.centerIn: parent; size: 24; visible: page.loading || page.refreshing; color: page.tint }
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
            readonly property bool partly: !ch.isRead && ch.lastPageRead > 0 && ch.pageCount > 0

            // ListView positions delegates itself, so the gutter lives on
            // the children rather than on x.
            width: list.width
            height: 68

            transform: Reveal {
                id: rr
                delay: Date.now() - page.openedAt < 2000 ? 380 + Math.min(row.index, 14) * 28 : 0
                duration: Date.now() - page.openedAt < 2000 ? Theme.slower : 1
                distance: 16
            }
            opacity: rr.progress

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.gutter - 14
                anchors.rightMargin: Theme.gutter - 14
                anchors.topMargin: 2
                anchors.bottomMargin: 2
                radius: Theme.radiusL
                color: row.isResume ? "transparent" : rowMouse.containsMouse ? Theme.hover : "transparent"
                gradient: row.isResume ? resumeGradient : null
                border.color: row.isResume ? Theme.alpha(page.tint, 0.32) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Gradient {
                    id: resumeGradient
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.alpha(page.tint, 0.16) }
                    GradientStop { position: 1; color: Theme.alpha(page.tint, 0.02) }
                }
            }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                anchors.leftMargin: Theme.gutter - 14
                anchors.rightMargin: Theme.gutter - 14
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
                anchors.leftMargin: Theme.gutter + 6
                anchors.rightMargin: Theme.gutter - 4
                spacing: 18

                Text {
                    // Chapter number, set large like an episode guide.
                    Layout.preferredWidth: 54
                    horizontalAlignment: Text.AlignRight
                    text: page.chapterLabel(row.ch)
                    font.family: Theme.display
                    font.italic: true
                    font.pixelSize: 26
                    font.weight: Font.Medium
                    font.features: { "lnum": 1, "tnum": 1 }
                    color: row.ch.isRead ? Theme.alpha(Theme.textFaint, 0.6) : row.isResume ? page.tint : Theme.alpha(Theme.text, 0.85)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        spacing: 10
                        Text {
                            Layout.fillWidth: true
                            text: row.ch.name
                            elide: Text.ElideRight
                            font.pixelSize: 15
                            font.weight: row.ch.isRead ? Font.Normal : Font.Medium
                            color: row.ch.isRead ? Theme.textFaint : Theme.text
                        }
                        Rectangle {
                            visible: row.isResume
                            implicitWidth: upNext.implicitWidth + 16
                            implicitHeight: 22
                            radius: 11
                            color: page.tint
                            Text {
                                id: upNext
                                anchors.centerIn: parent
                                text: page.started ? qsTr("UP NEXT") : qsTr("START HERE")
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1
                                color: Theme.onColor(page.tint)
                            }
                        }
                    }
                    RowLayout {
                        spacing: 10
                        Text {
                            text: {
                                const parts = []
                                if (row.ch.scanlator) parts.push(row.ch.scanlator)
                                const d = page.formatDate(row.ch.uploadDate)
                                if (d) parts.push(d)
                                if (row.partly)
                                    parts.push(qsTr("page %1 of %2").arg(row.ch.lastPageRead + 1).arg(row.ch.pageCount))
                                return parts.join("  ·  ")
                            }
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            color: Theme.textFaint
                        }
                        Rectangle {
                            // In-chapter progress for a chapter left mid-way.
                            visible: row.partly
                            Layout.preferredWidth: 90
                            Layout.preferredHeight: 3
                            radius: 1.5
                            color: Theme.alpha("#FFFFFF", 0.1)
                            Rectangle {
                                height: parent.height
                                radius: 1.5
                                width: parent.width * (row.ch.lastPageRead + 1) / Math.max(1, row.ch.pageCount)
                                color: page.tint
                            }
                        }
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
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    glyph: row.ch.isRead ? Icons.eyeOff : Icons.eye
                    tip: row.ch.isRead ? qsTr("Mark unread") : qsTr("Mark read")
                    iconSize: 16
                    tint: Theme.textDim
                    onClicked: page.setRead([row.ch.id], !row.ch.isRead)
                }
                IconButton {
                    opacity: rowMouse.containsMouse || hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    glyph: Icons.ellipsisVertical
                    iconSize: 16
                    tint: Theme.textDim
                    onClicked: menu.popup()
                }
                Rectangle {
                    // Play affordance that slides in on hover.
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    radius: 18
                    color: rowMouse.containsMouse || row.isResume ? page.tint : "transparent"
                    scale: rowMouse.containsMouse || row.isResume ? 1 : 0.6
                    opacity: rowMouse.containsMouse || row.isResume ? 1 : 0
                    Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; glyph: Icons.play; size: 15; color: Theme.onColor(page.tint) }
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
