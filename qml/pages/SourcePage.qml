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
    property Item searchBox
    property int nextPage: 1
    property bool hasNext: true
    property bool loading: false
    property string error
    property int token: 0
    property var seenIds: ({})

    function reset() {
        items.clear()
        nextPage = 1
        hasNext = true
        seenIds = {}
        error = ""
        ++token
        loading = false
        loadMore()
    }

    function loadMore() {
        if (loading || !hasNext || (mode === "SEARCH" && !query))
            return
        loading = true
        const mine = token
        Api.browse(source.id, mode, nextPage, mode === "SEARCH" ? query : "", function (err, result) {
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
            items.append(fresh)
            hasNext = result.hasNextPage && result.mangas.length > 0
            nextPage += 1
        })
    }

    Component.onCompleted: reset()
    Shortcut { sequence: "Ctrl+F"; onActivated: page.searchBox.forceActiveFocus() }

    GridView {
        id: grid

        readonly property real available: width - Theme.gutter * 2 + 24
        readonly property int columns: Math.max(2, Math.floor(available / (Prefs.coverSize + 24)))
        readonly property real tileWidth: cellWidth - 24

        anchors.fill: parent
        leftMargin: Theme.gutter
        rightMargin: Theme.gutter - 24
        bottomMargin: 40
        cellWidth: Math.floor(available / columns)
        cellHeight: Math.round(tileWidth * 1.5) + 76
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

            Item { Layout.preferredHeight: 26 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                IconButton { glyph: Icons.arrowLeft; tip: qsTr("Back"); onClicked: app.back() }
                Cover {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: Theme.radiusM
                    source: Api.cover(page.source.iconUrl)
                }
                ColumnLayout {
                    spacing: 0
                    Text {
                        text: page.source.name
                        font.family: Theme.display
                        font.pixelSize: 30
                        font.weight: Font.Medium
                        color: Theme.text
                    }
                    Text {
                        text: page.source.displayName
                        font.pixelSize: 12
                        color: Theme.textFaint
                    }
                }
                Item { Layout.fillWidth: true }
            }

            Item { Layout.preferredHeight: 22 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Segmented {
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
                SearchField {
                    id: search
                    Component.onCompleted: page.searchBox = this
                    Layout.preferredWidth: 340
                    text: page.initialQuery
                    placeholderText: qsTr("Search %1").arg(page.source.name)
                    onAccepted: {
                        page.query = text.trim()
                        page.mode = page.query ? "SEARCH" : "POPULAR"
                        page.reset()
                    }
                }
            }

            Item { Layout.preferredHeight: 24 }
        }

        delegate: Item {
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight
            MangaCard {
                width: grid.tileWidth
                manga: parent.modelData
                onClicked: app.openManga(parent.modelData)
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

    Spinner {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 80
        size: 28
        visible: page.loading && items.count === 0
    }

    EmptyState {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 80
        visible: !page.loading && items.count === 0
        glyph: page.error ? Icons.circleAlert : Icons.search
        title: page.error ? qsTr("The source didn't answer")
             : page.mode === "SEARCH" && !page.query ? qsTr("Search %1").arg(page.source.name)
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
