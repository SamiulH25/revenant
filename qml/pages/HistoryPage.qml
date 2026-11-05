import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

Item {
    id: page

    property var entries: []
    property bool loading: true
    property string filterText

    // One entry per series (its most recent chapter), newest first.
    readonly property var shown: {
        const q = filterText.trim().toLowerCase()
        const seen = {}
        const out = []
        for (const c of entries) {
            if (seen[c.mangaId] || !c.manga)
                continue
            seen[c.mangaId] = true
            if (!q || c.manga.title.toLowerCase().includes(q))
                out.push(Object.assign({ day: dayLabel(c.lastReadAt) }, c))
        }
        return out
    }

    KeyedListModel { id: rows; sectionKey: "day" }
    onShownChanged: rows.sync(shown)

    function dayLabel(seconds) {
        const d = Api.readDate(seconds)
        const today = new Date()
        today.setHours(0, 0, 0, 0)
        const diff = Math.floor((today - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000)
        if (diff <= 0) return qsTr("Today")
        if (diff === 1) return qsTr("Yesterday")
        if (diff < 7) return d.toLocaleDateString(Qt.locale(), "dddd")
        return d.toLocaleDateString(Qt.locale(), "MMMM d, yyyy")
    }

    function reload() {
        Api.history(function (error, list) {
            loading = false
            if (error)
                return app.toast(error, "error")
            entries = list
        })
    }

    function resume(entry) {
        Api.manga(entry.mangaId, function (error, full) {
            if (error)
                return app.toast(error, "error")
            const chapters = full.chapters.nodes
            const current = chapters.find(c => c.id === entry.id)
            // Finished that chapter? Continue with the next one.
            const target = current && current.isRead ? Api.resumeChapter(chapters) : (current || Api.resumeChapter(chapters))
            if (target)
                app.openReader(full, target, chapters)
        })
    }

    Component.onCompleted: reload()
    StackView.onActivated: reload()
    Connections {
        target: app
        function onLibraryRevisionChanged() { page.reload() }
    }
    Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.gutter
        anchors.rightMargin: Theme.gutter
        anchors.topMargin: Theme.contentTop
        spacing: 24

        RowLayout {
            Layout.fillWidth: true
            SectionHeader {
                Layout.fillWidth: true
                eyebrow: qsTr("Recently read")
                title: qsTr("History")
            }
            SearchField {
                id: search
                Layout.alignment: Qt.AlignBottom
                Layout.preferredWidth: 280
                placeholderText: qsTr("Filter history")
                onTextChanged: page.filterText = text
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumWidth: 980
            clip: true
            model: rows
            spacing: 4
            bottomMargin: 40
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            section.property: "section"
            section.delegate: Text {
                required property string section
                width: list.width
                height: 48
                verticalAlignment: Text.AlignBottom
                bottomPadding: 10
                text: section
                font.family: Theme.display
                font.pixelSize: 18
                font.weight: Font.Medium
                color: Theme.textDim
            }

            delegate: Item {
                id: entry
                required property var modelData
                required property int index
                width: list.width
                height: 92
                transform: Reveal { id: rv; delay: Math.min(entry.index, 12) * Theme.stagger; distance: 14 }
                opacity: rv.progress

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusM
                    color: hover.containsMouse ? Theme.surface : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: app.openManga(entry.modelData.manga, historyCover)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 16
                    Cover {
                        id: historyCover
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 72
                        radius: Theme.radiusS
                        source: Api.mangaCover(entry.modelData.manga)
                        scale: hover.containsMouse ? 1.08 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: entry.modelData.manga.title
                            elide: Text.ElideRight
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            color: Theme.text
                        }
                        Text {
                            Layout.fillWidth: true
                            text: {
                                const c = entry.modelData
                                let s = c.name
                                if (!c.isRead && c.pageCount > 0)
                                    s += "  ·  " + qsTr("page %1 of %2").arg(c.lastPageRead + 1).arg(c.pageCount)
                                else if (c.isRead)
                                    s += "  ·  " + qsTr("finished")
                                return s
                            }
                            elide: Text.ElideRight
                            font.pixelSize: 13
                            color: Theme.textDim
                        }
                        RowLayout {
                            spacing: 10
                            Text {
                                text: Api.readDate(entry.modelData.lastReadAt).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                                font.pixelSize: 12
                                color: Theme.textFaint
                            }
                            Rectangle {
                                // How far into the chapter.
                                visible: !entry.modelData.isRead && entry.modelData.pageCount > 0
                                Layout.preferredWidth: 120
                                Layout.preferredHeight: 3
                                radius: 1.5
                                color: Theme.alpha("#FFFFFF", 0.1)
                                Rectangle {
                                    height: parent.height
                                    radius: 1.5
                                    width: parent.width * (entry.modelData.lastPageRead + 1) / Math.max(1, entry.modelData.pageCount)
                                    color: Theme.accent
                                }
                            }
                        }
                    }
                    PillButton {
                        implicitHeight: 36
                        primary: hover.containsMouse
                        glyph: Icons.play
                        text: qsTr("Resume")
                        onClicked: page.resume(entry.modelData)
                    }
                }
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        visible: !page.loading && rows.count === 0
        glyph: Icons.history
        title: page.filterText ? qsTr("No matches") : qsTr("No reading history")
        body: page.filterText ? "" : qsTr("Chapters you open will show up here.")
    }

    Spinner { anchors.centerIn: parent; size: 28; visible: page.loading }
}
