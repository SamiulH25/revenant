import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

// Link a title to tracker entries and edit status, progress and score.
Sheet {
    id: sheet

    property var manga
    property var trackers: []      // logged-in trackers
    property var records: []
    property int searchingTracker: -1
    property var results: []
    property bool searching: false

    title: qsTr("Tracking")
    subtitle: manga ? manga.title : ""
    preferredWidth: 640

    function openFor(m) {
        manga = m
        searchingTracker = -1
        results = []
        open()
        reload()
    }

    function reload() {
        busy = true
        Api.trackers(function (error, list) {
            if (error) {
                busy = false
                return app.toast(error, "error")
            }
            trackers = list.filter(t => t.isLoggedIn)
            Api.trackRecords(manga.id, function (err, recs) {
                busy = false
                records = err ? [] : recs
            })
        })
    }

    function recordFor(trackerId) {
        return records.find(r => r.trackerId === trackerId) || null
    }

    function search(trackerId, query) {
        searchingTracker = trackerId
        searching = true
        results = []
        Api.searchTracker(trackerId, query, function (error, list) {
            searching = false
            if (error)
                return app.toast(error, "error")
            results = list
        })
    }

    function bind(trackerId, remoteId) {
        busy = true
        Api.bindTrack(manga.id, trackerId, remoteId, function (error) {
            busy = false
            if (error)
                return app.toast(error, "error")
            searchingTracker = -1
            results = []
            reload()
            Api.trackProgress(manga.id)
        })
    }

    function update(record, patch) {
        Api.updateTrack(record.id, patch, function (error, updated) {
            if (error)
                return app.toast(error, "error")
            records = records.map(r => r.id === updated.id ? updated : r)
        })
    }

    Text {
        visible: !sheet.busy && sheet.trackers.length === 0
        Layout.fillWidth: true
        text: qsTr("Sign in to a tracker such as AniList or MyAnimeList in Settings to sync your progress.")
        wrapMode: Text.WordWrap
        font.pixelSize: 13
        color: Theme.textDim
    }
    PillButton {
        visible: !sheet.busy && sheet.trackers.length === 0
        glyph: Icons.settings
        text: qsTr("Open settings")
        onClicked: { sheet.close(); app.goTab("settings") }
    }

    Repeater {
        model: sheet.trackers
        delegate: Rectangle {
            id: card
            required property var modelData
            readonly property var tracker: modelData
            readonly property var record: sheet.recordFor(tracker.id)
            Layout.fillWidth: true
            implicitHeight: cardCol.implicitHeight + 32
            radius: Theme.radiusL
            color: Theme.surface
            border.color: Theme.stroke

            ColumnLayout {
                id: cardCol
                x: 16
                y: 16
                width: parent.width - 32
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Cover {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: Theme.radiusS
                        source: Api.cover(card.tracker.icon)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: card.tracker.name
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: Theme.text
                        }
                        Text {
                            Layout.fillWidth: true
                            text: card.record ? card.record.title : qsTr("Not linked")
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            color: card.record ? Theme.textDim : Theme.textFaint
                        }
                    }
                    IconButton {
                        visible: !!card.record && !!card.record.remoteUrl
                        glyph: Icons.externalLink
                        tip: qsTr("Open on %1").arg(card.tracker.name)
                        onClicked: Qt.openUrlExternally(card.record.remoteUrl)
                    }
                    PillButton {
                        implicitHeight: 34
                        visible: !card.record
                        glyph: Icons.link
                        text: qsTr("Link")
                        checked: sheet.searchingTracker === card.tracker.id
                        onClicked: sheet.search(card.tracker.id, sheet.manga.title)
                    }
                    IconButton {
                        visible: !!card.record
                        glyph: Icons.x
                        tip: qsTr("Unlink")
                        onClicked: Api.unbindTrack(card.record.id, false, error => { if (!error) sheet.reload() })
                    }
                }

                // Bound record: status, progress, score.
                GridLayout {
                    Layout.fillWidth: true
                    visible: !!card.record
                    columns: 3
                    columnSpacing: 10
                    rowSpacing: 4
                    Text { text: qsTr("Status"); font.pixelSize: 11; color: Theme.textFaint }
                    Text { text: qsTr("Chapters"); font.pixelSize: 11; color: Theme.textFaint }
                    Text { text: qsTr("Score"); font.pixelSize: 11; color: Theme.textFaint }
                    Dropdown {
                        Layout.fillWidth: true
                        model: card.tracker.statuses
                        textRole: "name"
                        valueRole: "value"
                        currentIndex: card.record ? card.tracker.statuses.findIndex(s => s.value === card.record.status) : -1
                        onActivated: sheet.update(card.record, { status: currentValue })
                    }
                    RowLayout {
                        spacing: 2
                        IconButton {
                            glyph: Icons.minus
                            iconSize: 14
                            enabled: !!card.record && card.record.lastChapterRead > 0
                            onClicked: sheet.update(card.record, { lastChapterRead: Math.max(0, Math.floor(card.record.lastChapterRead) - 1) })
                        }
                        TextBox {
                            Layout.preferredWidth: 90
                            horizontalAlignment: TextInput.AlignHCenter
                            text: card.record ? Math.floor(card.record.lastChapterRead) + (card.record.totalChapters ? " / " + card.record.totalChapters : "") : ""
                            onEditingFinished: {
                                const n = parseFloat(text)
                                if (!isNaN(n) && card.record && n !== card.record.lastChapterRead)
                                    sheet.update(card.record, { lastChapterRead: n })
                            }
                        }
                        IconButton {
                            glyph: Icons.plus
                            iconSize: 14
                            onClicked: sheet.update(card.record, { lastChapterRead: Math.floor(card.record.lastChapterRead) + 1 })
                        }
                    }
                    Dropdown {
                        Layout.fillWidth: true
                        model: card.tracker.scores
                        currentIndex: card.record ? card.tracker.scores.indexOf(card.record.displayScore) : -1
                        onActivated: i => sheet.update(card.record, { scoreString: card.tracker.scores[i] })
                    }
                }

                // Search results when linking.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: sheet.searchingTracker === card.tracker.id
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        TextBox {
                            id: query
                            Layout.fillWidth: true
                            text: sheet.manga ? sheet.manga.title : ""
                            onAccepted: sheet.search(card.tracker.id, text)
                        }
                        PillButton { implicitHeight: 38; glyph: Icons.search; text: qsTr("Search"); onClicked: sheet.search(card.tracker.id, query.text) }
                    }
                    Spinner { visible: sheet.searching; size: 18 }
                    Text {
                        visible: !sheet.searching && sheet.results.length === 0
                        text: qsTr("No matches.")
                        font.pixelSize: 12
                        color: Theme.textFaint
                    }
                    Repeater {
                        model: sheet.searchingTracker === card.tracker.id ? sheet.results.slice(0, 12) : []
                        delegate: Rectangle {
                            id: hit
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 86
                            radius: Theme.radiusM
                            color: hitHover.hovered ? Theme.hover : "transparent"
                            HoverHandler { id: hitHover }
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 12
                                Image {
                                    Layout.preferredWidth: 48
                                    Layout.preferredHeight: 70
                                    source: hit.modelData.coverUrl
                                    sourceSize.width: 96
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    clip: true
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        Layout.fillWidth: true
                                        text: hit.modelData.title
                                        elide: Text.ElideRight
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                        color: Theme.text
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: [hit.modelData.publishingType, hit.modelData.publishingStatus, hit.modelData.startDate,
                                               hit.modelData.totalChapters ? qsTr("%1 ch").arg(hit.modelData.totalChapters) : ""].filter(s => s).join("  ·  ")
                                        elide: Text.ElideRight
                                        font.pixelSize: 11
                                        color: Theme.textFaint
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: hit.modelData.summary
                                        maximumLineCount: 2
                                        wrapMode: Text.WordWrap
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        font.pixelSize: 11
                                        color: Theme.textDim
                                    }
                                }
                                PillButton {
                                    implicitHeight: 32
                                    primary: true
                                    text: qsTr("Link")
                                    onClicked: sheet.bind(card.tracker.id, hit.modelData.remoteId)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
