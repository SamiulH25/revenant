import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import Revenant

Item {
    id: page

    property var all: []
    property var categories: []       // user categories, without Default
    property bool loading: true
    property bool updating: false
    property string updateText
    property string filterText
    property Item searchBox
    // When the first data arrived; cards rise in only shortly after it.
    property real introAt: 0
    property int heroIndex: 0
    property color heroTint: Theme.accent
    property bool heroHovered: false
    // Lives in the grid header, which page-level code can't name.
    property var heroSwap

    readonly property bool scrolled: grid.contentY - grid.originY > 40

    readonly property var continueShelf: all
        .filter(m => m.lastReadChapter && Number(m.lastReadChapter.lastReadAt) > 0 && m.unreadCount > 0)
        .sort((a, b) => Number(b.lastReadChapter.lastReadAt) - Number(a.lastReadChapter.lastReadAt))
        .slice(0, 6)
    // With nothing in progress, feature the newest addition instead.
    readonly property var heroItems: continueShelf.length ? continueShelf
        : all.slice().sort((a, b) => Number(b.inLibraryAt) - Number(a.inLibraryAt)).slice(0, 1)
    readonly property var hero: heroItems.length ? heroItems[Math.min(heroIndex, heroItems.length - 1)] : null
    readonly property bool resuming: continueShelf.length > 0

    function categoryIds(m) {
        return m.categories ? m.categories.nodes.map(c => c.id) : []
    }

    function inCategory(m, id) {
        if (id < 0)
            return true
        const ids = categoryIds(m)
        return id === 0 ? ids.length === 0 : ids.indexOf(id) >= 0
    }

    // Tabs: All, each category, and Uncategorised when something is.
    readonly property var tabs: {
        const t = [{ id: -1, name: qsTr("All"), count: all.length }]
        for (const c of categories)
            t.push({ id: c.id, name: c.name, count: all.filter(m => inCategory(m, c.id)).length })
        const loose = all.filter(m => inCategory(m, 0)).length
        if (categories.length && loose)
            t.push({ id: 0, name: qsTr("Uncategorised"), count: loose })
        return t
    }

    readonly property int activeCategory: tabs.some(t => t.id === Prefs.libraryCategory) ? Prefs.libraryCategory : -1

    readonly property var shown: {
        const q = filterText.trim().toLowerCase()
        let list = all.filter(m => inCategory(m, activeCategory) && (!q || m.title.toLowerCase().includes(q)) && (!Prefs.libraryUnreadOnly || m.unreadCount > 0))
        const read = m => m.lastReadChapter ? Number(m.lastReadChapter.lastReadAt) : 0
        switch (Prefs.librarySort) {
        case "title": list.sort((a, b) => a.title.localeCompare(b.title)); break
        case "unread": list.sort((a, b) => b.unreadCount - a.unreadCount || a.title.localeCompare(b.title)); break
        case "added": list.sort((a, b) => Number(b.inLibraryAt) - Number(a.inLibraryAt)); break
        default: list.sort((a, b) => read(b) - read(a) || Number(b.inLibraryAt) - Number(a.inLibraryAt))
        }
        return list
    }

    KeyedListModel { id: gridModel }
    onShownChanged: gridModel.sync(shown)

    function progressOf(m) {
        const total = m.chapters ? m.chapters.totalCount : 0
        return total > 0 ? (total - m.unreadCount) / total : -1
    }

    // The chapter "Resume" would open: the one left mid-way, else the next unread.
    function resumeTarget(m) {
        if (!m) return null
        const last = m.lastReadChapter
        if (last && !last.isRead && Number(last.lastReadAt) > 0)
            return last
        return m.firstUnreadChapter || last
    }

    function ago(seconds) {
        const s = Date.now() / 1000 - Number(seconds)
        if (s < 90) return qsTr("just now")
        if (s < 3600) return qsTr("%1 minutes ago").arg(Math.round(s / 60))
        if (s < 86400) return Math.round(s / 3600) === 1 ? qsTr("an hour ago") : qsTr("%1 hours ago").arg(Math.round(s / 3600))
        if (s < 172800) return qsTr("yesterday")
        return qsTr("%1 days ago").arg(Math.round(s / 86400))
    }

    function reload() {
        Api.categories((error, list) => { if (!error) categories = list.filter(c => c.id !== 0) })
        Api.library(function (error, list) {
            loading = false
            if (error)
                return app.toast(error, "error")
            if (!introAt)
                introAt = Date.now()
            all = list
        })
    }

    function resume(manga) {
        Api.manga(manga.id, function (error, full) {
            if (error)
                return app.toast(error, "error")
            const chapters = full.chapters.nodes
            const chapter = Api.resumeChapter(chapters)
            if (chapter)
                app.openReader(full, chapter, chapters)
        })
    }

    function startUpdate() {
        if (updating)
            return
        updating = true
        updateText = qsTr("Checking sources…")
        Api.updateLibrary(function (error) {
            if (error) {
                updating = false
                return app.toast(error, "error")
            }
            updatePoll.start()
        })
    }

    function selectHero(i) {
        if (i === heroIndex)
            return
        heroIndex = i
        if (heroSwap) heroSwap.restart()
        rotate.restart()
    }

    onHeroChanged: {
        if (!hero || !hero.thumbnailUrl)
            return
        const key = Api.coverKey(hero.thumbnailUrl, hero.thumbnailUrlLastFetched)
        ImageCache.accent(key, c => { if (c) page.heroTint = Theme.vivid(c) })
    }
    onHeroTintChanged: if (StackView.status === StackView.Active) app.tint = heroTint
    StackView.onActivated: {
        app.tint = heroTint
        reload()
    }

    Timer {
        // The hero cycles through what you're reading; hovering holds it.
        id: rotate
        interval: 9000
        repeat: true
        running: page.heroItems.length > 1 && !page.heroHovered && page.StackView.status === StackView.Active
        onTriggered: page.selectHero((page.heroIndex + 1) % page.heroItems.length)
    }

    Timer {
        id: updatePoll
        interval: 1500
        repeat: true
        onTriggered: Api.libraryUpdateStatus(function (error, jobs) {
            if (error || !jobs.isRunning) {
                updatePoll.stop()
                page.updating = false
                page.reload()
                if (!error)
                    app.toast(qsTr("Library updated"))
                return
            }
            page.updateText = qsTr("Updating %1 of %2").arg(jobs.finishedJobs).arg(jobs.totalJobs)
        })
    }

    Component.onCompleted: reload()
    Connections {
        target: app
        function onLibraryRevisionChanged() { page.reload() }
        function onLibraryUpdateRequested() { page.startUpdate() }
    }

    Shortcut { sequence: "Ctrl+F"; onActivated: page.searchBox.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+R"; enabled: !page.updating; onActivated: page.startUpdate() }

    GridView {
        id: grid

        // Cells carry a gap on their right; the right margin is trimmed by
        // the same amount so columns sit flush with the header.
        readonly property int gap: 28
        readonly property real available: width - Theme.gutter * 2 + gap
        readonly property int columns: Math.max(2, Math.floor(available / (Prefs.coverSize + gap)))
        readonly property real tileWidth: cellWidth - gap

        anchors.fill: parent
        leftMargin: Theme.gutter
        rightMargin: Theme.gutter - gap
        bottomMargin: 60
        cellWidth: Math.floor(available / columns)
        cellHeight: Math.round(tileWidth * 1.5) + 84
        model: gridModel
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        cacheBuffer: 600

        // The header keeps growing as the hero and tabs lay out; stay at the
        // top until the reader scrolls on their own.
        property bool touched: false
        onMovementStarted: touched = true
        onCountChanged: if (!touched) Qt.callLater(positionViewAtBeginning)

        // Sorting and filtering glide cards to their new places.
        move: Transition { NumberAnimation { properties: "x,y"; duration: Theme.slower; easing.type: Easing.OutQuint } }
        moveDisplaced: Transition { NumberAnimation { properties: "x,y"; duration: Theme.slower; easing.type: Easing.OutQuint } }
        displaced: Transition { NumberAnimation { properties: "x,y"; duration: Theme.slower; easing.type: Easing.OutQuint } }
        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.slow }
                NumberAnimation { property: "scale"; from: 0.85; to: 1; duration: Theme.slower; easing.type: Easing.OutBack }
            }
        }
        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.normal }
                NumberAnimation { property: "scale"; to: 0.85; duration: Theme.normal }
            }
        }

        header: Item {
            width: grid.width - Theme.gutter * 2
            height: heroArea.height + controls.height + 30
            onHeightChanged: if (!grid.touched) Qt.callLater(grid.positionViewAtBeginning)

            // --- Hero ---------------------------------------------------------
            Item {
                id: heroArea
                x: -Theme.gutter
                width: grid.width
                height: page.hero ? 600 : Theme.contentTop
                visible: page.hero !== null

                HoverHandler { onHoveredChanged: page.heroHovered = hovered }

                Backdrop {
                    anchors.fill: parent
                    anchors.bottomMargin: -40
                    source: page.hero ? Api.mangaCover(page.hero) : ""
                    tint: page.heroTint
                    fadeStart: 0.55
                }

                Item {
                    id: heroCoverBox
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.gutter + 30
                    y: Theme.contentTop + 18
                    width: 270
                    height: 405

                    Glow {
                        anchors.centerIn: parent
                        width: parent.width * 2.6
                        height: parent.height * 1.7
                        color: page.heroTint
                        strength: 0.32
                        Behavior on color { ColorAnimation { duration: Theme.cinematic } }
                    }

                    MangaCard {
                        id: heroCard
                        anchors.fill: parent
                        manga: page.hero
                        showTitle: false
                        showLibraryMark: false
                        playable: page.resuming
                        progress: page.hero ? page.progressOf(page.hero) : -1
                        onClicked: app.openManga(page.hero, heroCard)
                        onPlay: page.resume(page.hero)
                    }
                }

                ColumnLayout {
                    id: heroText
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.gutter
                    anchors.right: heroCoverBox.left
                    anchors.rightMargin: 70
                    y: Theme.contentTop + 34
                    spacing: 0

                    readonly property var target: page.resumeTarget(page.hero)

                    Row {
                        spacing: 10
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: page.heroTint
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                running: Theme.ambientMotion && page.StackView.status === StackView.Active
                                NumberAnimation { from: 1; to: 0.3; duration: 1100; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.3; to: 1; duration: 1100; easing.type: Easing.InOutSine }
                            }
                        }
                        Text {
                            text: (page.resuming
                                   ? qsTr("Continue reading") + (page.hero.lastReadChapter ? "  ·  " + page.ago(page.hero.lastReadChapter.lastReadAt) : "")
                                   : qsTr("Newest in your library")).toUpperCase()
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.letterSpacing: 2.2
                            color: Theme.alpha(Qt.lighter(page.heroTint, 1.2), 0.95)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 16
                        text: page.hero ? page.hero.title : ""
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.family: Theme.display
                        font.pixelSize: text.length > 22 ? 54 : 68
                        font.weight: Font.Medium
                        font.letterSpacing: -1.6
                        lineHeight: 0.98
                        color: Theme.text
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 14
                        visible: !!heroText.target
                        text: {
                            const t = heroText.target
                            if (!t) return ""
                            let s = t.name
                            if (t.lastPageRead > 0 && t.pageCount > 0)
                                s += "  ·  " + qsTr("page %1 of %2").arg(t.lastPageRead + 1).arg(t.pageCount)
                            return s
                        }
                        elide: Text.ElideRight
                        font.pixelSize: 16
                        font.weight: Font.Medium
                        color: Theme.alpha(Theme.text, 0.9)
                    }

                    RowLayout {
                        Layout.topMargin: 16
                        spacing: 14
                        visible: !!(page.hero && page.hero.chapters && page.hero.chapters.totalCount)
                        Rectangle {
                            Layout.preferredWidth: 300
                            Layout.preferredHeight: 6
                            radius: 3
                            color: Qt.rgba(1, 1, 1, 0.12)
                            Rectangle {
                                height: parent.height
                                radius: 3
                                width: parent.width * Math.max(0.02, page.hero ? page.progressOf(page.hero) : 0)
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: Theme.alpha(page.heroTint, 0.6) }
                                    GradientStop { position: 1; color: page.heroTint }
                                }
                                Behavior on width { NumberAnimation { duration: Theme.slower; easing.type: Easing.OutQuint } }
                            }
                        }
                        Text {
                            text: page.hero && page.hero.chapters
                                  ? qsTr("%1 of %2 chapters").arg(page.hero.chapters.totalCount - page.hero.unreadCount).arg(page.hero.chapters.totalCount)
                                  : ""
                            font.pixelSize: 13
                            font.features: { "tnum": 1 }
                            color: Theme.textDim
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 640
                        Layout.topMargin: 20
                        visible: text.length > 0
                        text: page.hero && page.hero.description ? page.hero.description.trim() : ""
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font.pixelSize: 15
                        lineHeight: 1.45
                        color: Theme.textDim
                    }

                    RowLayout {
                        Layout.topMargin: 26
                        spacing: 12
                        PillButton {
                            implicitHeight: 50
                            primary: true
                            accent: page.heroTint
                            glyph: Icons.play
                            text: page.resuming ? qsTr("Resume") : qsTr("Start reading")
                            onClicked: page.resume(page.hero)
                        }
                        PillButton {
                            implicitHeight: 50
                            glyph: Icons.bookOpenText
                            text: qsTr("Details")
                            onClicked: app.openManga(page.hero, heroCard)
                        }
                    }
                }

                // The queue: everything in progress, as small covers.
                Row {
                    id: queue
                    visible: page.heroItems.length > 1
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.gutter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    spacing: 14

                    Repeater {
                        model: page.heroItems
                        delegate: Item {
                            id: q
                            required property var modelData
                            required property int index
                            readonly property bool current: index === page.heroIndex
                            width: 58
                            height: 104

                            Item {
                                width: parent.width
                                height: 87
                                y: q.current ? -6 : qHover.hovered ? -3 : 0
                                scale: q.current ? 1.06 : 1
                                Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
                                Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
                                RectangularShadow {
                                    anchors.fill: parent
                                    radius: 6
                                    blur: 16
                                    offset.y: 6
                                    color: q.current ? Theme.alpha(page.heroTint, 0.5) : Qt.rgba(0, 0, 0, 0.5)
                                }
                                Cover {
                                    anchors.fill: parent
                                    radius: 6
                                    source: Api.mangaCover(q.modelData)
                                    opacity: q.current || qHover.hovered ? 1 : 0.55
                                    Behavior on opacity { NumberAnimation { duration: Theme.normal } }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 6
                                    color: "transparent"
                                    border.width: q.current ? 2 : 1
                                    border.color: q.current ? page.heroTint : Theme.alpha("#FFFFFF", 0.1)
                                }
                            }

                            Rectangle {
                                // Countdown to the next title.
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 3
                                radius: 1.5
                                color: Qt.rgba(1, 1, 1, 0.12)
                                visible: q.current
                                Rectangle {
                                    id: countdown
                                    height: parent.height
                                    radius: 1.5
                                    color: page.heroTint
                                    NumberAnimation on width {
                                        id: fill
                                        running: q.current && rotate.running
                                        from: 0
                                        to: 58
                                        duration: rotate.interval
                                    }
                                }
                                Connections {
                                    target: rotate
                                    function onRunningChanged() { if (!rotate.running) countdown.width = 0 }
                                }
                            }

                            HoverHandler { id: qHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: page.selectHero(q.index) }
                            ToolTip.visible: qHover.hovered
                            ToolTip.text: q.modelData.title
                            ToolTip.delay: 400
                        }
                    }
                }

                // Hero content slides in afresh each time the title changes.
                Component.onCompleted: page.heroSwap = heroSwapAnim
                SequentialAnimation {
                    id: heroSwapAnim
                    ParallelAnimation {
                        NumberAnimation { target: heroText; property: "opacity"; to: 0; duration: 140 }
                        NumberAnimation { target: heroCoverBox; property: "opacity"; to: 0; duration: 140 }
                    }
                    ScriptAction { script: { heroText.anchors.leftMargin = Theme.gutter + 30 } }
                    ParallelAnimation {
                        NumberAnimation { target: heroText; property: "opacity"; to: 1; duration: Theme.slow; easing.type: Easing.OutCubic }
                        NumberAnimation { target: heroText; property: "anchors.leftMargin"; to: Theme.gutter; duration: Theme.slower; easing.type: Easing.OutQuint }
                        NumberAnimation { target: heroCoverBox; property: "opacity"; to: 1; duration: Theme.slow; easing.type: Easing.OutCubic }
                        NumberAnimation { target: heroCoverBox; property: "scale"; from: 0.9; to: 1; duration: Theme.slower; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                    }
                }
            }

            // --- Shelf controls ---------------------------------------------------
            ColumnLayout {
                id: controls
                y: heroArea.height + 18
                width: parent.width
                spacing: 18
                visible: page.all.length > 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: qsTr("Your library")
                        font.family: Theme.display
                        font.pixelSize: 32
                        font.weight: Font.Medium
                        font.letterSpacing: -0.6
                        color: Theme.text
                    }
                    Text {
                        Layout.alignment: Qt.AlignBaseline
                        text: Api.count(page.shown.length, qsTr("%1 title"), qsTr("%1 titles"))
                        font.pixelSize: 13
                        color: Theme.textFaint
                    }
                    Item { Layout.fillWidth: true }
                    SearchField {
                        Component.onCompleted: page.searchBox = this
                        Layout.preferredWidth: 240
                        placeholderText: qsTr("Filter library")
                        onTextChanged: page.filterText = text
                    }
                    Chip {
                        implicitHeight: 40
                        text: qsTr("Unread")
                        checked: Prefs.libraryUnreadOnly
                        onToggled: Prefs.libraryUnreadOnly = checked
                    }
                    Segmented {
                        implicitHeight: 40
                        value: Prefs.librarySort
                        model: [
                            { value: "recent", label: qsTr("Recent") },
                            { value: "unread", label: qsTr("Unread") },
                            { value: "title", label: qsTr("A–Z") },
                            { value: "added", label: qsTr("Added") }
                        ]
                        onActivated: v => Prefs.librarySort = v
                    }
                    IconButton {
                        implicitWidth: 40
                        implicitHeight: 40
                        filled: true
                        glyph: Icons.tag
                        tip: qsTr("Edit categories")
                        onClicked: categoriesSheet.open()
                    }
                    PillButton {
                        glyph: Icons.refreshCw
                        busy: page.updating
                        enabled: !page.updating && page.all.length > 0
                        text: page.updating ? page.updateText : qsTr("Update")
                        onClicked: page.startUpdate()
                    }
                }

                UnderlineTabs {
                    Layout.fillWidth: true
                    visible: page.tabs.length > 1
                    model: page.tabs
                    current: page.activeCategory
                    onPicked: id => Prefs.libraryCategory = id
                }
            }
        }

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight
            MangaCard {
                id: tile
                width: grid.tileWidth
                manga: cell.modelData
                showLibraryMark: false
                playable: cell.modelData.unreadCount > 0
                progress: page.progressOf(cell.modelData)
                subtitle: cell.modelData.unreadCount > 0
                          ? qsTr("%1 unread").arg(cell.modelData.unreadCount)
                          : (cell.modelData.chapters && cell.modelData.chapters.totalCount ? qsTr("Caught up") : (cell.modelData.source ? cell.modelData.source.displayName : ""))
                enterDelay: Date.now() - page.introAt < 1500 ? Math.min(cell.index, 24) * Theme.stagger + 200 : -1
                onClicked: app.openManga(cell.modelData, tile)
                onPlay: page.resume(cell.modelData)
            }
        }

        footer: Item { width: 1; height: 40 }
    }

    EmptyState {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 40
        visible: !page.loading && page.all.length === 0
        glyph: Icons.ghost
        title: qsTr("Nothing haunts these shelves yet")
        body: qsTr("Find something in Discover and add it to your library. It'll wait for you here.")
        PillButton { primary: true; glyph: Icons.compass; text: qsTr("Discover manga"); onClicked: app.goTab("browse") }
        PillButton { glyph: Icons.puzzle; text: qsTr("Extensions"); onClicked: app.goTab("extensions") }
    }

    Spinner {
        anchors.centerIn: parent
        size: 28
        visible: page.loading
    }

    CategoriesSheet { id: categoriesSheet; onChanged: page.reload() }

    // Text tabs with an accent underline that glides to the active one.
    component UnderlineTabs: Item {
        id: tabsRoot
        property var model: []
        property int current: -1
        signal picked(int id)
        implicitHeight: 40

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.stroke }

        Row {
            id: tabRow
            spacing: 26
            Repeater {
                id: tabRep
                model: tabsRoot.model
                delegate: AbstractButton {
                    id: t
                    required property var modelData
                    readonly property bool active: modelData.id === tabsRoot.current
                    height: tabsRoot.height
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: tabsRoot.picked(modelData.id)
                    background: null
                    contentItem: Row {
                        spacing: 7
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: t.modelData.name
                            font.pixelSize: 14
                            font.weight: t.active ? Font.DemiBold : Font.Medium
                            color: t.active ? Theme.text : t.hovered ? Theme.alpha(Theme.text, 0.85) : Theme.textDim
                            Behavior on color { ColorAnimation { duration: Theme.fast } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: t.modelData.count
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: t.active ? Theme.accent : Theme.textFaint
                        }
                    }
                }
            }
        }

        Rectangle {
            readonly property Item target: {
                for (let i = 0; i < tabRep.count; ++i)
                    if (tabsRoot.model[i].id === tabsRoot.current) return tabRep.itemAt(i)
                return null
            }
            visible: target !== null
            anchors.bottom: parent.bottom
            x: target ? target.x : 0
            width: target ? target.width : 0
            height: 2
            radius: 1
            color: Theme.accent
            Behavior on x { SpringAnimation { spring: 4; damping: 0.35; epsilon: 0.2 } }
            Behavior on width { SpringAnimation { spring: 4; damping: 0.35; epsilon: 0.2 } }
            RectangularShadow { anchors.fill: parent; blur: 10; color: Theme.alpha(Theme.accent, 0.7) }
        }
    }
}
