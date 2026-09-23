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

    readonly property var continueShelf: all
        .filter(m => m.lastReadChapter && Number(m.lastReadChapter.lastReadAt) > 0 && m.unreadCount > 0)
        .sort((a, b) => Number(b.lastReadChapter.lastReadAt) - Number(a.lastReadChapter.lastReadAt))
        .slice(0, 8)

    function categoryIds(m) {
        return m.categories ? m.categories.nodes.map(c => c.id) : []
    }

    function inCategory(m, id) {
        if (id < 0)
            return true
        const ids = categoryIds(m)
        return id === 0 ? ids.length === 0 : ids.indexOf(id) >= 0
    }

    // Tabs: All, each category, and Default when something is uncategorised.
    readonly property var tabs: {
        if (!categories.length)
            return []
        const t = [{ id: -1, name: qsTr("All"), count: all.length }]
        for (const c of categories)
            t.push({ id: c.id, name: c.name, count: all.filter(m => inCategory(m, c.id)).length })
        const loose = all.filter(m => inCategory(m, 0)).length
        if (loose)
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

    function reload() {
        Api.categories((error, list) => { if (!error) categories = list.filter(c => c.id !== 0) })
        Api.library(function (error, list) {
            loading = false
            if (error)
                return app.toast(error, "error")
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
    }
    StackView.onActivated: reload()

    Shortcut { sequence: "Ctrl+F"; onActivated: page.searchBox.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+R"; enabled: !page.updating; onActivated: page.startUpdate() }

    GridView {
        id: grid

        // Cells carry a 24px gutter on their right; the right margin is
        // trimmed by the same amount so columns sit flush with the header.
        readonly property real available: width - Theme.gutter * 2 + 24
        readonly property int columns: Math.max(2, Math.floor(available / (Prefs.coverSize + 24)))
        readonly property real tileWidth: cellWidth - 24

        anchors.fill: parent
        leftMargin: Theme.gutter
        rightMargin: Theme.gutter - 24
        bottomMargin: 40
        cellWidth: Math.floor(available / columns)
        cellHeight: Math.round(tileWidth * 1.5) + 76
        model: gridModel
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        header: Column {
            width: grid.width - Theme.gutter * 2
            spacing: 0

            Item { width: 1; height: 40 }

            RowLayout {
                width: parent.width
                spacing: 12

                SectionHeader {
                    Layout.fillWidth: true
                    eyebrow: page.all.length === 1 ? qsTr("1 title") : qsTr("%1 titles").arg(page.all.length)
                    title: qsTr("Library")
                }

                SearchField {
                    Component.onCompleted: page.searchBox = this
                    Layout.alignment: Qt.AlignBottom
                    Layout.preferredWidth: 260
                    placeholderText: qsTr("Filter library")
                    onTextChanged: page.filterText = text
                }

                IconButton {
                    Layout.alignment: Qt.AlignBottom
                    implicitWidth: 40
                    implicitHeight: 40
                    filled: true
                    glyph: Icons.tag
                    tip: qsTr("Edit categories")
                    onClicked: categoriesSheet.open()
                }

                PillButton {
                    Layout.alignment: Qt.AlignBottom
                    glyph: Icons.refreshCw
                    busy: page.updating
                    enabled: !page.updating && page.all.length > 0
                    text: page.updating ? page.updateText : qsTr("Update")
                    onClicked: page.startUpdate()
                }
            }

            Item { width: 1; height: 28; visible: page.continueShelf.length > 0 }

            Text {
                visible: page.continueShelf.length > 0
                text: qsTr("Continue reading")
                font.family: Theme.display
                font.pixelSize: 20
                font.weight: Font.Medium
                color: Theme.text
            }

            Item { width: 1; height: 14; visible: page.continueShelf.length > 0 }

            ListView {
                id: shelf
                visible: page.continueShelf.length > 0
                width: parent.width
                height: 150
                orientation: ListView.Horizontal
                spacing: 16
                clip: true
                model: page.continueShelf
                boundsBehavior: Flickable.StopAtBounds
                delegate: ContinueCard {
                    required property var modelData
                    manga: modelData
                    onOpen: app.openManga(modelData)
                    onResume: page.resume(modelData)
                }
            }

            Item { width: 1; height: 34 }

            Flow {
                width: parent.width
                visible: page.tabs.length > 0
                spacing: 8
                bottomPadding: 18
                Repeater {
                    model: page.tabs
                    Chip {
                        required property var modelData
                        checkable: false
                        checked: page.activeCategory === modelData.id
                        implicitHeight: 34
                        text: modelData.name + "  " + modelData.count
                        onClicked: Prefs.libraryCategory = modelData.id
                    }
                }
            }

            RowLayout {
                width: parent.width
                visible: page.all.length > 0
                Text {
                    text: page.activeCategory < 0 ? qsTr("All titles") : (page.tabs.find(t => t.id === page.activeCategory) || {}).name
                    font.family: Theme.display
                    font.pixelSize: 20
                    font.weight: Font.Medium
                    color: Theme.text
                }
                Item { Layout.fillWidth: true }
                Chip {
                    text: qsTr("Unread only")
                    checked: Prefs.libraryUnreadOnly
                    onToggled: Prefs.libraryUnreadOnly = checked
                }
                Segmented {
                    Layout.leftMargin: 8
                    value: Prefs.librarySort
                    model: [
                        { value: "recent", label: qsTr("Recent") },
                        { value: "unread", label: qsTr("Unread") },
                        { value: "title", label: qsTr("A–Z") },
                        { value: "added", label: qsTr("Added") }
                    ]
                    onActivated: v => Prefs.librarySort = v
                }
            }

            Item { width: 1; height: 20 }
        }

        delegate: Item {
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight
            MangaCard {
                width: grid.tileWidth
                manga: modelData
                showLibraryMark: false
                subtitle: modelData.source ? modelData.source.displayName : ""
                onClicked: app.openManga(modelData)
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 60
        visible: !page.loading && page.all.length === 0
        glyph: Icons.ghost
        title: qsTr("Nothing haunts these shelves yet")
        body: qsTr("Install an extension, find something in Browse, and add it to your library.")
        PillButton { primary: true; glyph: Icons.compass; text: qsTr("Browse sources"); onClicked: app.goTab("browse") }
        PillButton { glyph: Icons.puzzle; text: qsTr("Extensions"); onClicked: app.goTab("extensions") }
    }

    Spinner {
        anchors.centerIn: parent
        size: 28
        visible: page.loading
    }

    CategoriesSheet { id: categoriesSheet; onChanged: page.reload() }

    // Signals out instead of touching page ids: inline components can't see them.
    component ContinueCard: Item {
        id: cc
        property var manga
        signal open()
        signal resume()
        width: 360
        height: 150

        MouseArea {
            id: ccHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cc.open()
        }

        Rectangle {
            id: ccFrame
            anchors.fill: parent
            radius: Theme.radiusL
            color: Theme.surface
            border.color: ccHover.containsMouse ? Theme.alpha(Theme.accent, 0.4) : Theme.stroke
            clip: true
            Behavior on border.color { ColorAnimation { duration: Theme.normal } }

            Image {
                id: ccArt
                anchors.fill: parent
                source: Api.mangaCover(cc.manga)
                sourceSize.width: 128
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: ccArt
                blurEnabled: true
                blur: 1
                blurMax: 48
                opacity: 0.35
                saturation: 0.2
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.2; color: Theme.alpha(Theme.surface, 0.3) }
                    GradientStop { position: 1; color: Theme.alpha(Theme.surface, 0.95) }
                }
            }
        }

        Cover {
            id: ccCover
            x: 14
            y: 14
            width: (parent.height - 28) / 1.5
            height: parent.height - 28
            radius: Theme.radiusS
            source: Api.mangaCover(cc.manga)
        }

        ColumnLayout {
            anchors.left: ccCover.right
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Text {
                Layout.fillWidth: true
                text: cc.manga.title
                font.family: Theme.display
                font.pixelSize: 17
                font.weight: Font.Medium
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                color: Theme.text
            }
            Text {
                text: qsTr("%n unread", "", cc.manga.unreadCount)
                font.pixelSize: 12
                color: Theme.textDim
            }
            PillButton {
                Layout.topMargin: 4
                implicitHeight: 32
                primary: true
                glyph: Icons.play
                text: qsTr("Resume")
                onClicked: cc.resume()
            }
        }
    }
}
