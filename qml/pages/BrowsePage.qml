import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

Item {
    id: page

    property var sources: []
    property bool loading: true
    property string langFilter: ""

    // Global search state: one row per source, filled as each one answers.
    property string globalQuery: ""
    property int searchToken: 0
    ListModel { id: searchRows }

    readonly property var langs: {
        const seen = {}
        for (const s of sources) seen[s.lang] = true
        return Object.keys(seen).sort((a, b) => langName(a).localeCompare(langName(b)))
    }

    readonly property var shownSources: sources.filter(s =>
        (Prefs.showNsfw || s.contentWarning !== "NSFW") && (!langFilter || s.lang === langFilter))

    function langName(code) {
        if (code === "all") return qsTr("Multi")
        if (code === "other") return qsTr("Other")
        const name = Qt.locale(code).nativeLanguageName
        return name && Qt.locale(code).name !== "C" ? name.charAt(0).toUpperCase() + name.slice(1) : code.toUpperCase()
    }

    function reload() {
        Api.sources(function (error, list) {
            loading = false
            if (error)
                return app.toast(error, "error")
            sources = list
            if (!langFilter) {
                const preferred = Prefs.languages.find(l => list.some(s => s.lang === l && l !== "all"))
                if (preferred && langs.length > 1)
                    langFilter = preferred
            }
        })
    }

    function runGlobalSearch(query) {
        globalQuery = query.trim()
        searchRows.clear()
        const token = ++searchToken
        if (!globalQuery)
            return
        const targets = shownSources.slice(0, 40)
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
                if (error)
                    searchRows.set(row, { status: "error", error: error })
                else
                    searchRows.set(row, { status: "done", resultsJson: JSON.stringify(result.mangas.slice(0, 20)) })
                launch()
            })
        }
        // A few sources at a time keeps slow sites from starving the rest.
        for (let i = 0; i < 4; ++i)
            launch()
    }

    Component.onCompleted: reload()
    Connections {
        target: app
        function onStoreReadyChanged() { page.reload() }
    }

    Shortcut { sequence: "Ctrl+F"; onActivated: globalSearch.forceActiveFocus() }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.gutter
        anchors.rightMargin: Theme.gutter
        anchors.topMargin: 40
        spacing: 22

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            SectionHeader {
                Layout.fillWidth: true
                eyebrow: qsTr("%1 sources installed").arg(page.sources.length)
                title: qsTr("Browse")
            }
            SearchField {
                id: globalSearch
                Layout.alignment: Qt.AlignBottom
                Layout.preferredWidth: 380
                placeholderText: qsTr("Search every source…")
                onAccepted: page.runGlobalSearch(text)
            }
        }

        Flow {
            Layout.fillWidth: true
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

        // --- Source grid ---------------------------------------------------
        GridView {
            id: sourceGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !page.globalQuery
            clip: true
            readonly property int columns: Math.max(1, Math.floor(width / 300))
            cellWidth: width / columns
            cellHeight: 84
            model: page.shownSources
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            delegate: Item {
                id: tile
                required property var modelData
                width: sourceGrid.cellWidth
                height: sourceGrid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: 12
                    anchors.bottomMargin: 12
                    radius: Theme.radiusL
                    color: tileHover.containsMouse ? Theme.raised : Theme.surface
                    border.color: tileHover.containsMouse ? Theme.strokeStrong : Theme.stroke
                    Behavior on color { ColorAnimation { duration: Theme.fast } }

                    MouseArea {
                        id: tileHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: app.openSource(tile.modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 10
                        spacing: 12
                        Cover {
                            Layout.preferredWidth: 42
                            Layout.preferredHeight: 42
                            radius: Theme.radiusM
                            source: Api.cover(tile.modelData.iconUrl)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: tile.modelData.name
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
                            visible: tile.modelData.isConfigurable
                            glyph: Icons.settings
                            tip: qsTr("Source settings")
                            iconSize: 16
                            tint: Theme.textDim
                            onClicked: app.openSourceSettings(tile.modelData)
                        }
                        IconButton {
                            visible: tile.modelData.supportsLatest
                            glyph: Icons.clock
                            tip: qsTr("Latest updates")
                            iconSize: 16
                            tint: Theme.textDim
                            onClicked: app.openSource(Object.assign({ startLatest: true }, tile.modelData))
                        }
                    }
                }
            }
        }

        // --- Global search results -----------------------------------------
        ListView {
            id: resultsView
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.globalQuery.length > 0
            clip: true
            spacing: 28
            model: searchRows
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            header: RowLayout {
                width: resultsView.width
                height: 44
                Text {
                    text: qsTr("Results for “%1”").arg(page.globalQuery)
                    font.family: Theme.display
                    font.pixelSize: 20
                    color: Theme.text
                }
                Item { Layout.fillWidth: true }
                PillButton {
                    glyph: Icons.x
                    text: qsTr("Close search")
                    onClicked: { globalSearch.clear(); page.runGlobalSearch("") }
                }
            }

            delegate: ColumnLayout {
                id: row
                required property string sourceJson
                required property string resultsJson
                required property string status
                required property string error
                readonly property var source: JSON.parse(sourceJson)
                readonly property var mangas: JSON.parse(resultsJson)
                width: resultsView.width
                spacing: 12
                visible: status !== "done" || mangas.length > 0

                RowLayout {
                    spacing: 10
                    Cover { Layout.preferredWidth: 22; Layout.preferredHeight: 22; radius: 5; source: Api.cover(row.source.iconUrl) }
                    Text {
                        text: row.source.displayName
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        color: Theme.text
                    }
                    Spinner { visible: row.status === "loading"; size: 14 }
                    Text {
                        visible: row.status === "error"
                        text: row.error
                        elide: Text.ElideRight
                        Layout.maximumWidth: 500
                        font.pixelSize: 12
                        color: Theme.danger
                    }
                    Item { Layout.fillWidth: true }
                    PillButton {
                        visible: row.status === "done"
                        implicitHeight: 30
                        text: qsTr("See all")
                        glyph: Icons.arrowRight
                        onClicked: app.openSource(row.source, page.globalQuery)
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: row.status === "done" ? 250 : 0
                    orientation: ListView.Horizontal
                    spacing: 16
                    clip: true
                    model: row.mangas
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: MangaCard {
                        required property var modelData
                        width: 140
                        manga: modelData
                        onClicked: app.openManga(modelData)
                    }
                }
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        visible: !page.loading && page.sources.length === 0
        glyph: Icons.puzzle
        title: qsTr("No sources yet")
        body: qsTr("Sources come from extensions. Install one from the Keiyoushi catalog to start browsing.")
        PillButton { primary: true; glyph: Icons.puzzle; text: qsTr("Open extensions"); onClicked: app.goTab("extensions") }
    }

    Spinner { anchors.centerIn: parent; size: 28; visible: page.loading }
}
