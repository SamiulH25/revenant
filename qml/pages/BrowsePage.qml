import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import Revenant

// Discover: a feed of what's popular and new across your sources, a
// spotlight, and one search box that asks every source at once.
Item {
    id: page

    property var sources: []
    property bool loading: true
    property string langFilter: ""
    property string draft: ""

    // Global search: one row per source, filled as each one answers.
    property string globalQuery: ""
    property int searchToken: 0
    property int answered: 0
    property int asked: 0
    property var topMatches: []
    ListModel { id: searchRows }

    // Titles gathered from the first feed row, for the spotlight.
    property var spotlightPool: []
    property string spotlightSource: ""

    readonly property bool scrolled: (globalQuery ? results.contentY - results.originY : feed.contentY - feed.originY) > 40

    readonly property var langs: {
        const seen = {}
        for (const s of sources) seen[s.lang] = true
        return Object.keys(seen).sort((a, b) => langName(a).localeCompare(langName(b)))
    }

    readonly property var shownSources: sources.filter(s =>
        (Prefs.showNsfw || s.contentWarning !== "NSFW") && (!langFilter || s.lang === langFilter || s.id === "0"))

    // Sources the feed shows rows for: pinned, then recently opened, then the rest.
    readonly property var featured: {
        const out = []
        const add = s => { if (s && !out.some(o => o.id === s.id)) out.push(s) }
        for (const id of Prefs.pinnedSources) add(shownSources.find(s => s.id === id))
        for (const id of Prefs.recentSources) add(shownSources.find(s => s.id === id))
        for (const s of shownSources) if (out.length < 5) add(s)
        return out.slice(0, 6)
    }

    readonly property var sections: {
        const out = [{ kind: "spotlight" }]
        featured.forEach((s, i) => {
            out.push({ kind: "row", source: s, type: "POPULAR" })
            if (s.supportsLatest && i < 3)
                out.push({ kind: "row", source: s, type: "LATEST" })
        })
        out.push({ kind: "sources" })
        return out
    }

    function langName(code) {
        if (code === "all") return qsTr("Multi")
        if (code === "other") return qsTr("Other")
        if (code === "localsourcelang" || code === "") return qsTr("Local")
        const name = Qt.locale(code).nativeLanguageName
        return name && Qt.locale(code).name !== "C" ? name.charAt(0).toUpperCase() + name.slice(1) : code.toUpperCase()
    }

    function sourceName(s) {
        return s.id === "0" ? qsTr("On this computer") : s.displayName
    }

    function rowTitle(s, type) {
        if (s.id === "0")
            return type === "LATEST" ? qsTr("Recently added on this computer") : qsTr("On this computer")
        return (type === "LATEST" ? qsTr("Fresh on %1") : qsTr("Popular on %1")).arg(s.displayName)
    }

    function isPinned(s) { return Prefs.pinnedSources.indexOf(s.id) >= 0 }
    function togglePin(s) {
        const list = Prefs.pinnedSources.slice()
        const i = list.indexOf(s.id)
        if (i >= 0) list.splice(i, 1)
        else list.unshift(s.id)
        Prefs.pinnedSources = list
    }

    function openSource(s, query) {
        Prefs.recentSources = [s.id].concat(Prefs.recentSources.filter(id => id !== s.id)).slice(0, 8)
        app.openSource(s, query)
    }

    function reload() {
        Api.sources(function (error, list) {
            loading = false
            if (error)
                return app.toast(error, "error")
            sources = list
            if (!langFilter) {
                const preferred = Prefs.languages.find(l => list.some(s => s.lang === l && l !== "all"))
                if (preferred && langs.length > 2)
                    langFilter = preferred
            }
        }, true)
    }

    function noteSpotlight(source, mangas) {
        if (spotlightPool.length || !mangas.length)
            return
        spotlightSource = source.id === "0" ? qsTr("from this computer") : qsTr("popular on %1").arg(source.displayName)
        spotlightPool = mangas.slice(0, 6)
    }

    // 0 = no match; higher is closer.
    function relevance(q, title) {
        const s = (title || "").toLowerCase()
        if (s === q) return 120
        if (s.startsWith(q)) return 100
        if (s.split(/[\s\-:&·]+/).some(w => w.startsWith(q))) return 80
        const at = s.indexOf(q)
        if (at >= 0) return 60 - Math.min(30, at)
        const words = q.split(/\s+/).filter(w => w)
        const hits = words.filter(w => s.includes(w)).length
        return hits ? 20 + hits * 10 : 5
    }

    function rankTopMatches() {
        const q = globalQuery.toLowerCase()
        const seen = {}
        const pool = []
        for (let i = 0; i < searchRows.count; ++i) {
            const row = searchRows.get(i)
            if (row.status !== "done")
                continue
            const source = JSON.parse(row.sourceJson)
            for (const m of JSON.parse(row.resultsJson)) {
                const key = m.title.toLowerCase().replace(/[^a-z0-9]+/g, "")
                if (seen[key])
                    continue
                seen[key] = true
                pool.push(Object.assign({ _score: relevance(q, m.title), _source: source.displayName }, m))
            }
        }
        topMatches = pool.sort((a, b) => b._score - a._score).slice(0, 12)
    }

    function runGlobalSearch(query) {
        globalQuery = query.trim()
        draft = globalQuery
        searchRows.clear()
        topMatches = []
        answered = 0
        results.touched = false
        const token = ++searchToken
        if (!globalQuery) {
            asked = 0
            return
        }
        Prefs.recentSearches = [globalQuery].concat(Prefs.recentSearches.filter(s => s.toLowerCase() !== globalQuery.toLowerCase())).slice(0, 8)
        const targets = shownSources.slice(0, 40)
        asked = targets.length
        let next = 0
        const launch = () => {
            if (token !== searchToken || next >= targets.length)
                return
            const source = targets[next++]
            const row = searchRows.count
            // Roles hold JSON so delegates get plain objects, not nested models.
            searchRows.append({ sourceJson: JSON.stringify(source), resultsJson: "[]", status: "loading", error: "" })
            Api.browse(source.id, "SEARCH", 1, globalQuery, function (error, result) {
                if (token !== searchToken)
                    return
                answered++
                if (error)
                    searchRows.set(row, { status: "error", error: error })
                else
                    searchRows.set(row, { status: "done", resultsJson: JSON.stringify(result.mangas.slice(0, 20)) })
                rankTopMatches()
                launch()
            })
        }
        // A few sources at a time keeps slow sites from starving the rest.
        for (let i = 0; i < 4; ++i)
            launch()
    }

    function surprise() {
        const pool = spotlightPool.length ? spotlightPool : topMatches
        if (pool.length)
            app.peekManga(pool[Math.floor(Math.random() * pool.length)], null, pool)
    }

    Component.onCompleted: {
        reload()
        if (app.pendingSearch) {
            const q = app.pendingSearch
            app.pendingSearch = ""
            Qt.callLater(() => page.runGlobalSearch(q))
        }
    }
    Connections {
        target: app
        function onStoreReadyChanged() { page.reload() }
    }

    Shortcut { sequence: "Ctrl+F"; onActivated: page.focusSearch() }
    property Item searchField
    function focusSearch() {
        if (globalQuery) results.positionViewAtBeginning()
        else feed.positionViewAtBeginning()
        if (searchField) searchField.forceActiveFocus()
    }

    // --- Feed ------------------------------------------------------------------
    ListView {
        id: feed
        anchors.fill: parent
        visible: !page.globalQuery
        model: page.sections
        spacing: 46
        cacheBuffer: 1400
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        property bool touched: false
        onMovementStarted: touched = true
        header: SearchHero {
            width: feed.width
            onHeightChanged: if (!feed.touched) Qt.callLater(feed.positionViewAtBeginning)
        }
        footer: Item { width: 1; height: 60 }

        delegate: Loader {
            id: section
            required property var modelData
            required property int index
            width: feed.width
            sourceComponent: modelData.kind === "spotlight" ? spotlightComponent
                           : modelData.kind === "row" ? rowComponent : sourcesComponent
            onLoaded: {
                if (item.hasOwnProperty("source")) {
                    // Type first: setting the source starts the load.
                    item.type = modelData.type
                    item.source = modelData.source
                }
            }
        }
    }

    // --- Search results ----------------------------------------------------------
    ListView {
        id: results
        anchors.fill: parent
        visible: page.globalQuery.length > 0
        model: searchRows
        spacing: 40
        cacheBuffer: 1400
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        footer: Item { width: 1; height: 60 }

        property bool touched: false
        onMovementStarted: touched = true
        onVisibleChanged: if (visible) { touched = false; Qt.callLater(positionViewAtBeginning) }
        header: Column {
            width: results.width
            spacing: 0
            onHeightChanged: if (!results.touched) Qt.callLater(results.positionViewAtBeginning)
            SearchHero { width: parent.width; compact: true }

            // Progress across sources.
            RowLayout {
                x: Theme.gutter
                width: parent.width - Theme.gutter * 2
                spacing: 14
                Text {
                    text: qsTr("Results for “%1”").arg(page.globalQuery)
                    font.family: Theme.display
                    font.pixelSize: 30
                    font.weight: Font.Medium
                    color: Theme.text
                }
                Item { Layout.fillWidth: true }
                Spinner { size: 16; visible: page.answered < page.asked }
                Text {
                    text: page.answered < page.asked
                          ? qsTr("%1 of %2 sources answered").arg(page.answered).arg(page.asked)
                          : qsTr("All %1 sources answered").arg(page.asked)
                    font.pixelSize: 13
                    color: Theme.textDim
                }
                PillButton {
                    glyph: Icons.x
                    text: qsTr("Clear")
                    onClicked: page.runGlobalSearch("")
                }
            }
            Item {
                x: Theme.gutter
                width: parent.width - Theme.gutter * 2
                height: 18
                Rectangle {
                    y: 10
                    width: parent.width
                    height: 3
                    radius: 1.5
                    color: Theme.alpha("#FFFFFF", 0.06)
                    Rectangle {
                        height: parent.height
                        radius: 1.5
                        width: parent.width * (page.asked ? page.answered / page.asked : 0)
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutQuint } }
                    }
                }
            }

            Item { width: 1; height: 26 }

            // Best matches across every source, deduplicated.
            Column {
                x: Theme.gutter
                width: parent.width - Theme.gutter * 2
                spacing: 16
                visible: page.topMatches.length > 0
                RowLayout {
                    width: parent.width
                    Icon { glyph: Icons.sparkles; size: 18; color: Theme.accent }
                    Text {
                        text: qsTr("Top matches")
                        font.family: Theme.display
                        font.pixelSize: 22
                        color: Theme.text
                    }
                    Item { Layout.fillWidth: true }
                }
                Flow {
                    width: parent.width
                    spacing: 22
                    Repeater {
                        model: page.topMatches
                        delegate: MangaCard {
                            id: topCard
                            required property var modelData
                            required property int index
                            width: 150
                            manga: modelData
                            subtitle: modelData._source
                            enterDelay: index * Theme.stagger
                            onClicked: app.peekManga(modelData, topCard, page.topMatches)
                        }
                    }
                }
                Item { width: 1; height: 20 }
            }
        }

        delegate: Item {
            id: resultRow
            required property string sourceJson
            required property string resultsJson
            required property string status
            required property string error
            readonly property var source: JSON.parse(sourceJson)
            readonly property var mangas: JSON.parse(resultsJson)
            width: results.width
            height: visible ? rowBody.height : 0
            visible: status !== "done" || mangas.length > 0

            ShelfRow {
                id: rowBody
                width: parent.width
                title: page.sourceName(resultRow.source)
                subtitle: page.langName(resultRow.source.lang)
                icon: resultRow.source.id !== "0" ? Api.cover(resultRow.source.iconUrl) : ""
                glyph: resultRow.source.id === "0" ? Icons.monitor : ""
                mangas: resultRow.mangas
                phase: resultRow.status
                errorText: resultRow.error
                onSeeAll: page.openSource(resultRow.source, page.globalQuery)
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 120
        visible: !page.loading && page.sources.length === 0
        glyph: Icons.puzzle
        title: qsTr("No sources yet")
        body: qsTr("Sources come from extensions. Install one from the Keiyoushi catalog to start discovering.")
        PillButton { primary: true; glyph: Icons.puzzle; text: qsTr("Open extensions"); onClicked: app.goTab("extensions") }
    }

    // --- Pieces ------------------------------------------------------------------

    component SearchHero: Item {
        id: hero
        property bool compact: false
        height: Theme.contentTop + (compact ? 150 : 300)

        Glow {
            x: parent.width * 0.5 - width / 2
            y: Theme.contentTop - 160
            width: parent.width * 0.9
            height: 420
            strength: 0.14
        }

        ColumnLayout {
            x: Theme.gutter
            y: Theme.contentTop + (hero.compact ? 0 : 20)
            width: parent.width - Theme.gutter * 2
            spacing: 0

            Text {
                visible: !hero.compact
                text: qsTr("Discover").toUpperCase()
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.letterSpacing: 2.4
                color: Theme.accent
            }
            Text {
                visible: !hero.compact
                Layout.topMargin: 10
                text: qsTr("Find your next obsession.")
                font.family: Theme.display
                font.pixelSize: 58
                font.weight: Font.Medium
                font.letterSpacing: -1.6
                color: Theme.text
            }
            Text {
                visible: !hero.compact
                Layout.topMargin: 8
                text: page.sources.length
                      ? qsTr("One search across %1. Or wander the shelves below.").arg(Api.count(page.sources.length, qsTr("%1 source"), qsTr("%1 sources")))
                      : qsTr("Install an extension to start exploring.")
                font.pixelSize: 15
                color: Theme.textDim
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: hero.compact ? 0 : 28
                spacing: 12

                Item {
                    Layout.preferredWidth: Math.min(720, hero.width - Theme.gutter * 2 - 200)
                    Layout.preferredHeight: 60

                    RectangularShadow {
                        anchors.fill: parent
                        radius: 30
                        blur: 30
                        spread: -4
                        color: Theme.alpha(Theme.accent, field.activeFocus ? 0.35 : 0)
                        Behavior on color { ColorAnimation { duration: Theme.slow } }
                    }
                    TextField {
                        id: field
                        anchors.fill: parent
                        Component.onCompleted: if (!hero.compact) page.searchField = field
                        leftPadding: 58
                        rightPadding: 130
                        text: page.draft
                        placeholderText: qsTr("Search every source…")
                        placeholderTextColor: Theme.textFaint
                        color: Theme.text
                        selectionColor: Theme.alpha(Theme.accent, 0.35)
                        font.pixelSize: 18
                        verticalAlignment: TextInput.AlignVCenter
                        onTextEdited: page.draft = text
                        onAccepted: page.runGlobalSearch(text)
                        background: Rectangle {
                            radius: 30
                            color: field.activeFocus ? Theme.alpha(Theme.raised, 0.95) : Theme.alpha(Theme.surface, 0.85)
                            border.color: field.activeFocus ? Theme.alpha(Theme.accent, 0.6) : Theme.strokeStrong
                            Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                            Icon {
                                anchors.left: parent.left
                                anchors.leftMargin: 22
                                anchors.verticalCenter: parent.verticalCenter
                                glyph: Icons.search
                                size: 20
                                color: field.activeFocus ? Theme.accent : Theme.textDim
                            }
                        }
                        Keys.onEscapePressed: event => {
                            if (text.length) { page.draft = ""; text = ""; event.accepted = true }
                            else { focus = false; event.accepted = false }
                        }
                    }
                    PillButton {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: 44
                        primary: true
                        text: qsTr("Search")
                        enabled: field.text.trim().length > 0
                        onClicked: page.runGlobalSearch(field.text)
                    }
                }

                PillButton {
                    implicitHeight: 60
                    visible: !hero.compact
                    glyph: Icons.dices
                    text: qsTr("Surprise me")
                    enabled: page.spotlightPool.length > 0
                    onClicked: page.surprise()
                }
                Item { Layout.fillWidth: true }
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 16
                spacing: 8
                visible: !hero.compact && Prefs.recentSearches.length > 0
                Text {
                    height: 30
                    verticalAlignment: Text.AlignVCenter
                    rightPadding: 4
                    text: qsTr("Recent")
                    font.pixelSize: 12
                    color: Theme.textFaint
                }
                Repeater {
                    model: Prefs.recentSearches
                    Chip {
                        required property string modelData
                        checkable: false
                        text: modelData
                        onClicked: page.runGlobalSearch(modelData)
                    }
                }
            }
        }
    }

    // A titled, horizontally scrolling shelf of cards with arrows on hover.
    component ShelfRow: Item {
        id: shelf
        property string title
        property string subtitle
        property string icon
        property string glyph
        property var mangas: []
        property string phase: "loading"      // loading | done | error
        property string errorText
        property bool canSeeAll: true
        signal seeAll()
        signal retry()

        height: 52 + 312

        HoverHandler { id: shelfHover }

        RowLayout {
            x: Theme.gutter
            width: parent.width - Theme.gutter * 2
            height: 40
            spacing: 12
            Cover {
                visible: shelf.icon.length > 0
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 8
                source: shelf.icon
            }
            Icon { visible: shelf.glyph.length > 0; glyph: shelf.glyph; size: 20; color: Theme.accent }
            Text {
                text: shelf.title
                font.family: Theme.display
                font.pixelSize: 24
                font.weight: Font.Medium
                color: Theme.text
            }
            Text {
                Layout.alignment: Qt.AlignBaseline
                text: shelf.subtitle
                font.pixelSize: 12
                color: Theme.textFaint
            }
            Spinner { size: 14; visible: shelf.phase === "loading" }
            Item { Layout.fillWidth: true }
            Text {
                visible: shelf.phase === "error"
                Layout.maximumWidth: 420
                text: shelf.errorText
                elide: Text.ElideRight
                font.pixelSize: 12
                color: Theme.danger
            }
            PillButton {
                visible: shelf.phase === "error"
                implicitHeight: 32
                glyph: Icons.refreshCw
                text: qsTr("Retry")
                onClicked: shelf.retry()
            }
            IconButton {
                visible: shelf.phase === "done"
                glyph: Icons.chevronLeft
                enabled: strip.contentX > strip.originX + 1
                onClicked: strip.page(-1)
            }
            IconButton {
                visible: shelf.phase === "done"
                glyph: Icons.chevronRight
                enabled: strip.contentX + strip.width < strip.contentWidth + strip.originX - 1
                onClicked: strip.page(1)
            }
            PillButton {
                visible: shelf.canSeeAll && shelf.phase !== "error"
                implicitHeight: 34
                text: qsTr("See all")
                glyph: Icons.arrowRight
                onClicked: shelf.seeAll()
            }
        }

        ListView {
            id: strip
            y: 58
            width: parent.width
            height: 300
            orientation: ListView.Horizontal
            spacing: 22
            leftMargin: Theme.gutter
            rightMargin: Theme.gutter
            clip: false
            visible: shelf.phase === "done"
            model: shelf.mangas
            boundsBehavior: Flickable.StopAtBounds
            function page(dir) {
                const target = Math.max(originX - leftMargin, Math.min(contentWidth + originX + rightMargin - width, contentX + dir * width * 0.8))
                slide.to = target
                slide.restart()
            }
            NumberAnimation { id: slide; target: strip; property: "contentX"; duration: Theme.slower; easing.type: Easing.OutQuint }
            delegate: MangaCard {
                id: rowCard
                required property var modelData
                required property int index
                width: 158
                manga: modelData
                enterDelay: index * Theme.stagger
                onClicked: app.peekManga(modelData, rowCard, shelf.mangas)
            }
        }

        Row {
            // Skeleton cards while the source answers.
            x: Theme.gutter
            y: 58
            spacing: 22
            visible: shelf.phase === "loading"
            Repeater {
                model: Math.ceil((shelf.width - Theme.gutter * 2) / 180)
                Column {
                    required property int index
                    spacing: 10
                    Skeleton { width: 158; height: 237; delay: index * 90 }
                    Skeleton { width: 120; height: 12; radius: 6; delay: index * 90 }
                    Skeleton { width: 70; height: 10; radius: 5; delay: index * 90 }
                }
            }
        }
    }

    Component {
        id: rowComponent
        ShelfRow {
            id: feedRow
            property var source
            property string type: "POPULAR"
            title: source ? page.rowTitle(source, type) : ""
            subtitle: source ? page.langName(source.lang) : ""
            icon: source && source.id !== "0" ? Api.cover(source.iconUrl) : ""
            glyph: source && source.id === "0" ? Icons.monitor : ""
            onSourceChanged: load()
            onRetry: load()
            onSeeAll: page.openSource(type === "LATEST" ? Object.assign({ startLatest: true }, source) : source)
            function load() {
                if (!source)
                    return
                phase = "loading"
                Api.browse(source.id, type, 1, "", (error, result) => {
                    if (error) {
                        feedRow.phase = "error"
                        feedRow.errorText = error
                        return
                    }
                    feedRow.mangas = result.mangas.slice(0, 24)
                    feedRow.phase = "done"
                    if (feedRow.type === "POPULAR")
                        page.noteSpotlight(feedRow.source, feedRow.mangas)
                })
            }
        }
    }

    Component {
        id: spotlightComponent
        Spotlight {}
    }

    // Featured titles, one at a time, cycling on their own.
    component Spotlight: Item {
        id: spot
        property int index: 0
        property var details: ({})
        property color tint: Theme.accent
        readonly property var pool: page.spotlightPool
        readonly property var current: pool.length ? pool[Math.min(index, pool.length - 1)] : null
        readonly property var full: current ? (details[current.id] || current) : null
        height: pool.length ? 400 : 0
        visible: pool.length > 0

        function go(i) {
            if (!pool.length)
                return
            index = (i + pool.length) % pool.length
            swap.restart()
            cycle.restart()
        }

        onCurrentChanged: {
            if (!current)
                return
            const m = current
            if (m.thumbnailUrl)
                ImageCache.accent(Api.coverKey(m.thumbnailUrl, m.thumbnailUrlLastFetched), c => { if (c && spot.current === m) spot.tint = Theme.vivid(c) })
            if (details[m.id])
                return
            Api.manga(m.id, (error, f) => {
                const store = x => { const d = Object.assign({}, spot.details); d[m.id] = x; spot.details = d }
                if (!error && f.initialized && f.description)
                    return store(f)
                Api.refreshManga(m.id, (err, fresh) => { if (!err) store(fresh) })
            })
        }

        Timer {
            id: cycle
            interval: 8000
            repeat: true
            running: spot.pool.length > 1 && !spotHover.hovered && feed.visible
            onTriggered: spot.go(spot.index + 1)
        }

        HoverHandler { id: spotHover }

        Item {
            id: card
            x: Theme.gutter
            width: parent.width - Theme.gutter * 2
            height: parent.height

            RectangularShadow {
                anchors.fill: parent
                radius: Theme.radiusXL
                blur: 50
                offset.y: 24
                color: Theme.alpha(spot.tint, 0.22)
                Behavior on color { ColorAnimation { duration: Theme.cinematic } }
            }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: spotMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
                Rectangle { anchors.fill: parent; color: Theme.surface }
                Backdrop {
                    anchors.fill: parent
                    source: spot.current ? Api.mangaCover(spot.current) : ""
                    tint: spot.tint
                    intensity: 0.85
                    fadeStart: 0.85
                }
            }
            Item {
                id: spotMask
                anchors.fill: parent
                layer.enabled: true
                visible: false
                Rectangle { anchors.fill: parent; radius: Theme.radiusXL }
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusXL
                color: "transparent"
                border.color: Theme.alpha("#FFFFFF", 0.08)
            }

            MangaCard {
                id: spotCover
                x: 44
                y: 44
                width: 208
                showTitle: false
                showLibraryMark: false
                manga: spot.current
                onClicked: app.peekManga(spot.current, spotCover, spot.pool)
            }

            ColumnLayout {
                id: spotText
                anchors.left: spotCover.right
                anchors.leftMargin: 48
                anchors.right: parent.right
                anchors.rightMargin: 56
                y: 56
                spacing: 0

                Text {
                    text: (qsTr("Spotlight") + "  ·  " + page.spotlightSource).toUpperCase()
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2.2
                    color: Qt.lighter(spot.tint, 1.2)
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    text: spot.current ? spot.current.title : ""
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: Theme.display
                    font.pixelSize: 52
                    font.weight: Font.Medium
                    font.letterSpacing: -1.4
                    lineHeight: 0.98
                    color: Theme.text
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    spacing: 6
                    Repeater {
                        model: spot.full && spot.full.genre ? spot.full.genre.slice(0, 5) : []
                        Rectangle {
                            required property string modelData
                            implicitWidth: gl.implicitWidth + 20
                            implicitHeight: 26
                            radius: 13
                            color: Theme.alpha(spot.tint, 0.14)
                            border.color: Theme.alpha(spot.tint, 0.32)
                            Text { id: gl; anchors.centerIn: parent; text: modelData; font.pixelSize: 12; color: Theme.alpha(Theme.text, 0.9) }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 720
                    Layout.topMargin: 16
                    text: spot.full && spot.full.description ? spot.full.description.trim() : ""
                    visible: text.length > 0
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.pixelSize: 15
                    lineHeight: 1.45
                    color: Theme.textDim
                }
                RowLayout {
                    Layout.topMargin: 24
                    spacing: 10
                    PillButton {
                        implicitHeight: 48
                        primary: true
                        accent: spot.tint
                        glyph: Icons.scanEye
                        text: qsTr("Take a look")
                        onClicked: app.peekManga(spot.current, spotCover, spot.pool)
                    }
                    PillButton {
                        implicitHeight: 48
                        glyph: Icons.bookOpenText
                        text: qsTr("Details")
                        onClicked: app.openManga(spot.current, spotCover)
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 26
                spacing: 8
                IconButton { glyph: Icons.chevronLeft; filled: true; onClicked: spot.go(spot.index - 1) }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Repeater {
                        model: spot.pool.length
                        Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: index === spot.index ? 22 : 7
                            height: 7
                            radius: 3.5
                            color: index === spot.index ? spot.tint : Theme.alpha("#FFFFFF", 0.25)
                            Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutQuint } }
                            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: spot.go(index) }
                        }
                    }
                }
                IconButton { glyph: Icons.chevronRight; filled: true; onClicked: spot.go(spot.index + 1) }
            }

            SequentialAnimation {
                id: swap
                ParallelAnimation {
                    NumberAnimation { target: spotText; property: "opacity"; from: 0; to: 1; duration: Theme.slow; easing.type: Easing.OutCubic }
                    NumberAnimation { target: spotText; property: "anchors.leftMargin"; from: 80; to: 48; duration: Theme.slower; easing.type: Easing.OutQuint }
                    NumberAnimation { target: spotCover; property: "scale"; from: 0.88; to: 1; duration: Theme.slower; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                    NumberAnimation { target: spotCover; property: "rotation"; from: -4; to: 0; duration: Theme.slower; easing.type: Easing.OutBack }
                }
            }
        }
    }

    Component {
        id: sourcesComponent
        Column {
            spacing: 18

            RowLayout {
                x: Theme.gutter
                width: parent.width - Theme.gutter * 2
                Text {
                    text: qsTr("All sources")
                    font.family: Theme.display
                    font.pixelSize: 28
                    font.weight: Font.Medium
                    color: Theme.text
                }
                Text {
                    Layout.alignment: Qt.AlignBaseline
                    Layout.leftMargin: 8
                    text: Api.count(page.shownSources.length, qsTr("%1 source"), qsTr("%1 sources"))
                    font.pixelSize: 12
                    color: Theme.textFaint
                }
                Item { Layout.fillWidth: true }
            }

            Flow {
                x: Theme.gutter
                width: parent.width - Theme.gutter * 2
                spacing: 8
                visible: page.langs.length > 1
                Chip {
                    text: qsTr("All languages")
                    checkable: false
                    checked: page.langFilter === ""
                    onClicked: page.langFilter = ""
                }
                Repeater {
                    model: page.langs
                    Chip {
                        required property string modelData
                        text: page.langName(modelData)
                        checkable: false
                        checked: page.langFilter === modelData
                        onClicked: page.langFilter = checked ? "" : modelData
                    }
                }
            }

            Grid {
                id: sourceGrid
                x: Theme.gutter
                width: parent.width - Theme.gutter * 2
                columns: Math.max(1, Math.floor((width + 14) / 330))
                columnSpacing: 14
                rowSpacing: 14
                readonly property real tileW: (width - columnSpacing * (columns - 1)) / columns

                Repeater {
                    model: page.shownSources
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        width: sourceGrid.tileW
                        height: 76
                        radius: Theme.radiusL
                        color: tileHover.hovered ? Theme.raised : Theme.alpha(Theme.surface, 0.8)
                        border.color: page.isPinned(modelData) ? Theme.alpha(Theme.accent, 0.4) : tileHover.hovered ? Theme.strokeStrong : Theme.stroke
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                        transform: Reveal { id: tr; delay: Math.min(tile.index, 20) * 20; distance: 12 }
                        opacity: tr.progress

                        HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: page.openSource(tile.modelData) }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10
                            spacing: 12
                            Item {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 44
                                Cover {
                                    anchors.fill: parent
                                    visible: tile.modelData.id !== "0"
                                    radius: Theme.radiusM
                                    source: Api.cover(tile.modelData.iconUrl)
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    visible: tile.modelData.id === "0"
                                    radius: Theme.radiusM
                                    color: Theme.alpha(Theme.accent, 0.14)
                                    Icon { anchors.centerIn: parent; glyph: Icons.monitor; size: 20; color: Theme.accent }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: page.sourceName(tile.modelData)
                                    elide: Text.ElideRight
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    color: Theme.text
                                }
                                RowLayout {
                                    spacing: 6
                                    Text {
                                        text: page.langName(tile.modelData.lang)
                                        font.pixelSize: 12
                                        color: Theme.textFaint
                                    }
                                    Text {
                                        visible: tile.modelData.contentWarning === "NSFW"
                                        text: "18+"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: Theme.nsfw
                                    }
                                }
                            }
                            IconButton {
                                glyph: page.isPinned(tile.modelData) ? Icons.pin : Icons.pin
                                checked: page.isPinned(tile.modelData)
                                opacity: checked || tileHover.hovered ? 1 : 0
                                tip: checked ? qsTr("Unpin from Discover") : qsTr("Pin to Discover")
                                iconSize: 15
                                tint: Theme.textDim
                                onClicked: page.togglePin(tile.modelData)
                            }
                            IconButton {
                                visible: tile.modelData.isConfigurable
                                glyph: Icons.settings
                                tip: qsTr("Source settings")
                                iconSize: 15
                                tint: Theme.textDim
                                onClicked: app.openSourceSettings(tile.modelData)
                            }
                            IconButton {
                                visible: tile.modelData.supportsLatest
                                glyph: Icons.clock
                                tip: qsTr("Latest updates")
                                iconSize: 15
                                tint: Theme.textDim
                                onClicked: page.openSource(Object.assign({ startLatest: true }, tile.modelData))
                            }
                        }
                    }
                }
            }
        }
    }

    Spinner { anchors.centerIn: parent; size: 28; visible: page.loading }
}
