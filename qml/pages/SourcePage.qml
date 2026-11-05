import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

Item {
    id: page

    property var source
    property string initialQuery

    property string mode: initialQuery ? "SEARCH" : (source && source.startLatest ? "LATEST" : "POPULAR")
    property string query: initialQuery
    // Appending keeps the scroll position; reassigning a JS array would
    // reset the view on every page.
    KeyedListModel { id: items }
    // The same titles as a plain list, for the peek drawer to step through.
    property var loaded: []
    property Item searchBox
    property int nextPage: 1
    property bool hasNext: true
    property bool loading: false
    property string error
    property int token: 0
    property var seenIds: ({})
    property var filterChanges: []
    // Each batch rises in; this is when the latest one landed.
    property real batchAt: 0
    property int batchStart: 0
    readonly property bool searching: mode === "SEARCH"
    readonly property bool local: !!source && source.id === "0"
    readonly property bool scrolled: grid.contentY - grid.originY > 40

    function reset() {
        items.clear()
        loaded = []
        nextPage = 1
        hasNext = true
        seenIds = {}
        error = ""
        ++token
        loading = false
        loadMore()
    }

    function loadMore() {
        if (loading || !hasNext || (searching && !query && filterChanges.length === 0))
            return
        loading = true
        const mine = token
        Api.browse(source.id, mode, nextPage, searching ? query : "", function (err, result) {
            if (mine !== token)
                return
            loading = false
            if (err) {
                error = err
                return
            }
            // Sources sometimes repeat entries across pages; keep the first.
            const fresh = result.mangas.filter(m => !seenIds[m.id])
            fresh.forEach(m => seenIds[m.id] = true)
            batchStart = items.count
            batchAt = Date.now()
            items.append(fresh)
            loaded = loaded.concat(fresh)
            hasNext = result.hasNextPage && result.mangas.length > 0
            nextPage += 1
        }, searching ? filterChanges : [])
    }

    Component.onCompleted: reset()

    FilterSheet {
        id: filterSheet
        onApplied: changes => {
            page.filterChanges = changes
            page.mode = changes.length || page.query ? "SEARCH" : "POPULAR"
            page.reset()
        }
    }
    Shortcut { sequence: "Ctrl+F"; onActivated: page.searchBox.forceActiveFocus() }

    GridView {
        id: grid

        readonly property int gap: 28
        readonly property real available: width - Theme.gutter * 2 + gap
        readonly property int columns: Math.max(2, Math.floor(available / (Prefs.coverSize + gap)))
        readonly property real tileWidth: cellWidth - gap

        anchors.fill: parent
        leftMargin: Theme.gutter
        rightMargin: Theme.gutter - gap
        bottomMargin: 40
        cellWidth: Math.floor(available / columns)
        cellHeight: Math.round(tileWidth * 1.5) + 84
        model: items
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        cacheBuffer: 1200

        function maybeLoad() {
            if (contentY + height > contentHeight + originY - 900)
                page.loadMore()
        }
        onContentYChanged: maybeLoad()
        // A short first page may not fill the view; keep pulling until it does.
        onContentHeightChanged: Qt.callLater(maybeLoad)

        header: ColumnLayout {
            width: grid.width - Theme.gutter * 2
            spacing: 0

            Item { Layout.preferredHeight: Theme.contentTop - 8 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                IconButton { glyph: Icons.arrowLeft; tip: qsTr("Back"); filled: true; onClicked: app.back() }
                Item {
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    Glow { anchors.centerIn: parent; width: 150; height: 150; strength: 0.18 }
                    Cover {
                        anchors.fill: parent
                        visible: !page.local
                        radius: Theme.radiusL
                        source: Api.cover(page.source.iconUrl)
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: page.local
                        radius: Theme.radiusL
                        color: Theme.alpha(Theme.accent, 0.14)
                        Icon { anchors.centerIn: parent; glyph: Icons.monitor; size: 24; color: Theme.accent }
                    }
                }
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: page.local ? qsTr("On this computer") : page.source.name
                        font.family: Theme.display
                        font.pixelSize: 38
                        font.weight: Font.Medium
                        font.letterSpacing: -0.8
                        color: Theme.text
                    }
                    Text {
                        text: page.local ? qsTr("Manga in Revenant's local folder") : page.source.displayName
                        font.pixelSize: 13
                        color: Theme.textFaint
                    }
                }
                Item { Layout.fillWidth: true }
            }

            Item { Layout.preferredHeight: 24 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Segmented {
                    implicitHeight: 40
                    value: page.mode
                    model: {
                        const m = [{ value: "POPULAR", label: qsTr("Popular"), glyph: Icons.flame }]
                        if (page.source.supportsLatest)
                            m.push({ value: "LATEST", label: qsTr("Latest"), glyph: Icons.clock })
                        m.push({ value: "SEARCH", label: qsTr("Search"), glyph: Icons.search })
                        return m
                    }
                    onActivated: v => {
                        page.mode = v
                        if (v === "SEARCH")
                            search.forceActiveFocus()
                        page.reset()
                    }
                }
                Item { Layout.fillWidth: true }
                PillButton {
                    glyph: Icons.slidersHorizontal
                    checked: page.filterChanges.length > 0
                    text: page.filterChanges.length ? qsTr("Filters · %1").arg(page.filterChanges.length) : qsTr("Filters")
                    onClicked: {
                        filterSheet.load(page.source.id)
                        filterSheet.open()
                    }
                }
                IconButton {
                    visible: page.source.isConfigurable
                    implicitWidth: 40
                    implicitHeight: 40
                    glyph: Icons.settings
                    tip: qsTr("Source settings")
                    filled: true
                    onClicked: app.openSourceSettings(page.source)
                }
                SearchField {
                    id: search
                    Component.onCompleted: page.searchBox = this
                    Layout.preferredWidth: 340
                    text: page.initialQuery
                    placeholderText: qsTr("Search %1").arg(page.local ? qsTr("this computer") : page.source.name)
                    onAccepted: {
                        page.query = text.trim()
                        page.mode = page.query || page.filterChanges.length ? "SEARCH" : "POPULAR"
                        page.reset()
                    }
                }
            }

            Item { Layout.preferredHeight: 28 }
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
                enterDelay: Date.now() - page.batchAt < 1200 && cell.index >= page.batchStart
                            ? Math.min(cell.index - page.batchStart, 24) * Theme.stagger : -1
                onClicked: app.peekManga(cell.modelData, tile, page.loaded)
            }
        }

        footer: Item {
            width: grid.width - Theme.gutter * 2
            height: 90
            Spinner {
                anchors.centerIn: parent
                size: 22
                visible: page.loading && items.count > 0
            }
            PillButton {
                anchors.centerIn: parent
                visible: !page.loading && page.error.length > 0 && items.count > 0
                glyph: Icons.refreshCw
                text: qsTr("Retry")
                onClicked: { page.error = ""; page.loadMore() }
            }
        }
    }

    Grid {
        // Skeleton tiles while the first page loads.
        x: Theme.gutter
        y: Theme.contentTop + 170
        visible: page.loading && items.count === 0
        columns: grid.columns
        columnSpacing: grid.gap
        rowSpacing: 30
        Repeater {
            model: grid.columns * 2
            Column {
                required property int index
                spacing: 10
                Skeleton { width: grid.tileWidth; height: grid.tileWidth * 1.5; delay: index * 70 }
                Skeleton { width: grid.tileWidth * 0.75; height: 12; radius: 6; delay: index * 70 }
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 80
        visible: !page.loading && items.count === 0
        glyph: page.error ? Icons.circleAlert : Icons.search
        title: page.error ? qsTr("The source didn't answer")
             : page.searching && !page.query && !page.filterChanges.length ? qsTr("Search %1").arg(page.local ? qsTr("this computer") : page.source.name)
             : qsTr("Nothing here")
        body: page.error ? page.error : ""
        PillButton {
            visible: page.error.length > 0
            primary: true
            glyph: Icons.refreshCw
            text: qsTr("Try again")
            onClicked: page.reset()
        }
    }
}
