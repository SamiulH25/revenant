import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

Item {
    id: page

    property string view: "queue"    // queue | disk
    property var onDisk: []           // [{ manga, chapters: [...] }]
    property bool diskLoading: false

    KeyedListModel { id: queueRows; key: "chapterId" }
    readonly property var queueEntries: app.downloadQueue.map(d => Object.assign({ chapterId: d.chapter.id }, d))
    onQueueEntriesChanged: queueRows.sync(queueEntries)
    Component.onCompleted: queueRows.sync(queueEntries)

    KeyedListModel { id: diskRows }
    onOnDiskChanged: diskRows.sync(onDisk)

    function stateLabel(d) {
        switch (d.state) {
        case "DOWNLOADING": return qsTr("Downloading · %1%").arg(Math.round(d.progress * 100))
        case "ERROR": return d.tries > 1 ? qsTr("Failed after %1 tries").arg(d.tries) : qsTr("Failed")
        case "FINISHED": return qsTr("Done")
        default: return app.downloaderRunning ? qsTr("Waiting") : qsTr("Paused")
        }
    }

    function loadDisk() {
        diskLoading = true
        Api.downloadedChapters(function (error, chapters) {
            diskLoading = false
            if (error)
                return app.toast(error, "error")
            const groups = {}
            const order = []
            for (const c of chapters) {
                if (!groups[c.mangaId]) {
                    groups[c.mangaId] = { id: c.mangaId, manga: c.manga, chapters: [] }
                    order.push(c.mangaId)
                }
                groups[c.mangaId].chapters.push(c)
            }
            onDisk = order.map(id => groups[id]).sort((a, b) => a.manga.title.localeCompare(b.manga.title))
        })
    }

    function deleteManga(group) {
        Api.deleteDownloads(group.chapters.map(c => c.id), function (error) {
            if (error)
                return app.toast(error, "error")
            app.toast(Api.count(group.chapters.length, qsTr("Deleted %1 chapter"), qsTr("Deleted %1 chapters")))
            loadDisk()
            app.libraryRevision++
        })
    }

    function move(d, delta) {
        const to = Math.max(0, Math.min(app.downloadQueue.length - 1, d.position + delta))
        Api.reorderDownload(d.chapter.id, to, (error, status) => {
            if (error) return app.toast(error, "error")
            app.applyDownloadStatus(status)
        })
    }

    Connections {
        target: app
        function onDownloadsSettled() { if (page.view === "disk") page.loadDisk() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.gutter
        anchors.rightMargin: Theme.gutter
        anchors.topMargin: 40
        spacing: 22

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            SectionHeader {
                Layout.fillWidth: true
                eyebrow: app.activeDownloads
                         ? (app.downloaderRunning ? qsTr("%n downloading", "", app.activeDownloads) : qsTr("%n paused", "", app.activeDownloads))
                         : qsTr("Queue empty")
                title: qsTr("Downloads")
            }
            PillButton {
                Layout.alignment: Qt.AlignBottom
                visible: app.activeDownloads > 0
                primary: !app.downloaderRunning
                glyph: app.downloaderRunning ? Icons.pause : Icons.play
                text: app.downloaderRunning ? qsTr("Pause") : qsTr("Resume")
                onClicked: Api.downloader(app.downloaderRunning ? "stop" : "start", (e, s) => { if (!e) app.applyDownloadStatus(s) })
            }
            PillButton {
                Layout.alignment: Qt.AlignBottom
                visible: app.activeDownloads > 0
                glyph: Icons.x
                text: qsTr("Clear queue")
                onClicked: Api.downloader("clear", (e, s) => { if (!e) app.applyDownloadStatus(s) })
            }
        }

        Segmented {
            value: page.view
            model: [
                { value: "queue", label: qsTr("Queue · %1").arg(app.activeDownloads), glyph: Icons.download },
                { value: "disk", label: qsTr("On disk"), glyph: Icons.packageIcon }
            ]
            onActivated: v => {
                page.view = v
                if (v === "disk") page.loadDisk()
            }
        }

        // --- Queue ------------------------------------------------------------
        ListView {
            id: queueList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumWidth: 1000
            visible: page.view === "queue"
            clip: true
            spacing: 6
            model: queueRows
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: entry
                required property var modelData
                readonly property var d: modelData
                width: queueList.width
                height: 76
                radius: Theme.radiusM
                color: hover.hovered ? Theme.surface : "transparent"
                HoverHandler { id: hover }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 14
                    Cover {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 56
                        radius: Theme.radiusS
                        source: Api.mangaCover(entry.d.manga)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true
                                text: entry.d.manga.title + "  ·  " + entry.d.chapter.name
                                elide: Text.ElideRight
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                color: Theme.text
                            }
                            Text {
                                text: page.stateLabel(entry.d)
                                font.pixelSize: 12
                                font.features: { "tnum": 1 }
                                color: entry.d.state === "ERROR" ? Theme.danger : entry.d.state === "DOWNLOADING" ? Theme.accent : Theme.textFaint
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            radius: 2
                            color: Theme.overlay
                            Rectangle {
                                width: parent.width * entry.d.progress
                                height: 4
                                radius: 2
                                color: entry.d.state === "ERROR" ? Theme.danger : Theme.accent
                                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                    Row {
                        opacity: hover.hovered ? 1 : 0.35
                        IconButton { glyph: Icons.chevronUp; tip: qsTr("Move up"); iconSize: 16; enabled: entry.d.position > 0; onClicked: page.move(entry.d, -1) }
                        IconButton { glyph: Icons.chevronDown; tip: qsTr("Move down"); iconSize: 16; enabled: entry.d.position < app.activeDownloads - 1; onClicked: page.move(entry.d, 1) }
                        IconButton {
                            glyph: Icons.x
                            tip: qsTr("Remove from queue")
                            iconSize: 16
                            onClicked: Api.dequeueDownloads([entry.d.chapter.id], (e, s) => { if (!e) app.applyDownloadStatus(s) })
                        }
                    }
                }
            }
        }

        // --- On disk ----------------------------------------------------------
        ListView {
            id: diskList
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumWidth: 1000
            visible: page.view === "disk"
            clip: true
            spacing: 6
            model: diskRows
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            delegate: Rectangle {
                id: group
                required property var modelData
                width: diskList.width
                height: 84
                radius: Theme.radiusM
                color: groupHover.hovered ? Theme.surface : "transparent"
                HoverHandler { id: groupHover }
                TapHandler { onTapped: app.openManga(group.modelData.manga) }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 14
                    Cover {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 64
                        radius: Theme.radiusS
                        source: Api.mangaCover(group.modelData.manga)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: group.modelData.manga.title
                            elide: Text.ElideRight
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: Theme.text
                        }
                        Text {
                            Layout.fillWidth: true
                            text: Api.count(group.modelData.chapters.length, qsTr("%1 chapter"), qsTr("%1 chapters")) + "  ·  "
                                  + group.modelData.chapters.slice(0, 4).map(c => c.name).join(", ")
                                  + (group.modelData.chapters.length > 4 ? "…" : "")
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            color: Theme.textDim
                        }
                    }
                    PillButton {
                        implicitHeight: 34
                        glyph: Icons.trash2
                        text: qsTr("Delete")
                        onClicked: page.deleteManga(group.modelData)
                    }
                }
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        visible: page.view === "queue" ? app.activeDownloads === 0 : (!page.diskLoading && page.onDisk.length === 0)
        glyph: page.view === "queue" ? Icons.download : Icons.packageIcon
        title: page.view === "queue" ? qsTr("Nothing downloading") : qsTr("Nothing saved for offline")
        body: qsTr("Download chapters from a title's page to read them without a connection.")
    }

    Spinner { anchors.centerIn: parent; size: 28; visible: page.view === "disk" && page.diskLoading }
}
