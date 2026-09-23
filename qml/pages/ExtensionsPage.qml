import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

Item {
    id: page

    property var all: []
    property bool loading: true
    property bool refreshing: false
    property string view: "all"      // all | installed | updates
    property string filterText
    property string langFilter: ""

    property var busy: ({})

    readonly property int installedCount: all.filter(e => e.isInstalled).length
    readonly property var updatable: all.filter(e => e.hasUpdate)

    readonly property var langs: {
        const seen = {}
        for (const e of all) seen[e.lang] = true
        return Object.keys(seen).sort()
    }

    // Alphabetical everywhere, so installing a row never moves it.
    readonly property var shown: {
        const q = filterText.trim().toLowerCase()
        return all.filter(e => {
            if (!Prefs.showNsfw && e.contentWarning === "NSFW" && !e.isInstalled) return false
            if (view === "installed" && !e.isInstalled) return false
            if (view === "updates" && !e.hasUpdate) return false
            if (langFilter && e.lang !== langFilter) return false
            return !q || e.name.toLowerCase().includes(q) || e.pkgName.includes(q)
        })
    }

    KeyedListModel { id: rows; key: "pkgName" }
    onShownChanged: rows.sync(shown)

    function langName(code) {
        if (code === "all") return qsTr("Multi")
        if (code === "other") return qsTr("Other")
        const loc = Qt.locale(code)
        const name = loc.nativeLanguageName
        return name && loc.name !== "C" ? name.charAt(0).toUpperCase() + name.slice(1) : code.toUpperCase()
    }

    function load(list) {
        all = list.slice().sort((a, b) => a.name.localeCompare(b.name) || a.lang.localeCompare(b.lang))
        loading = false
    }

    function reload() {
        Api.extensions(function (error, list) {
            if (error) {
                loading = false
                return app.toast(error, "error")
            }
            load(list)
        })
    }

    function refreshIndex() {
        refreshing = true
        Api.refreshExtensions(function (error, list) {
            refreshing = false
            if (error)
                return app.toast(error, "error")
            load(list)
            app.toast(qsTr("Extension index refreshed"))
        })
    }

    function act(ext, action) {
        const b = Object.assign({}, busy)
        b[ext.pkgName] = true
        busy = b
        Api.setExtension(ext.pkgName, action, function (error, updated) {
            const nb = Object.assign({}, busy)
            delete nb[ext.pkgName]
            busy = nb
            if (error)
                return app.toast(qsTr("%1: %2").arg(ext.name).arg(error), "error")
            all = all.map(e => e.pkgName === ext.pkgName ? Object.assign({}, e, updated) : e)
            const verb = action === "install" ? qsTr("Installed") : action === "update" ? qsTr("Updated") : qsTr("Removed")
            app.toast(qsTr("%1 %2").arg(verb).arg(ext.name))
        })
    }

    function updateAll() {
        for (const e of updatable)
            act(e, "update")
    }

    Component.onCompleted: reload()
    Connections {
        target: app
        function onStoreReadyChanged() { page.reload() }
    }
    Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.gutter
        anchors.rightMargin: Theme.gutter
        anchors.topMargin: 40
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            SectionHeader {
                Layout.fillWidth: true
                eyebrow: qsTr("Keiyoushi · %1 available").arg(page.all.length)
                title: qsTr("Extensions")
            }
            PillButton {
                Layout.alignment: Qt.AlignBottom
                visible: page.updatable.length > 0
                primary: true
                glyph: Icons.download
                text: qsTr("Update all (%1)").arg(page.updatable.length)
                onClicked: page.updateAll()
            }
            PillButton {
                Layout.alignment: Qt.AlignBottom
                glyph: Icons.refreshCw
                busy: page.refreshing
                text: qsTr("Refresh index")
                onClicked: page.refreshIndex()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Segmented {
                value: page.view
                model: [
                    { value: "all", label: qsTr("All") },
                    { value: "installed", label: qsTr("Installed · %1").arg(page.installedCount) },
                    { value: "updates", label: qsTr("Updates · %1").arg(page.updatable.length) }
                ]
                onActivated: v => page.view = v
            }
            Dropdown {
                Layout.preferredWidth: 180
                model: [{ code: "", label: qsTr("All languages") }].concat(page.langs.map(c => ({ code: c, label: page.langName(c) })))
                textRole: "label"
                valueRole: "code"
                onActivated: page.langFilter = currentValue
            }
            Item { Layout.fillWidth: true }
            SearchField {
                id: search
                Layout.preferredWidth: 300
                placeholderText: qsTr("Find an extension")
                onTextChanged: page.filterText = text
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: rows
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            cacheBuffer: 800
            bottomMargin: 30

            delegate: Rectangle {
                id: rowItem
                required property var modelData
                readonly property var ext: modelData
                readonly property bool working: !!page.busy[modelData.pkgName]

                width: list.width
                height: 66
                radius: Theme.radiusM
                color: rowHover.hovered ? Theme.surface : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.fast } }

                HoverHandler { id: rowHover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 14

                    Cover {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        radius: Theme.radiusM
                        source: Api.cover(rowItem.ext.iconUrl)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: rowItem.ext.name
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: Theme.text
                            }
                            Rectangle {
                                visible: rowItem.ext.contentWarning === "NSFW"
                                implicitWidth: nsfwLabel.implicitWidth + 10
                                implicitHeight: 18
                                radius: 9
                                color: Theme.alpha(Theme.nsfw, 0.14)
                                Text { id: nsfwLabel; anchors.centerIn: parent; text: "18+"; font.pixelSize: 10; font.weight: Font.Bold; color: Theme.nsfw }
                            }
                            Rectangle {
                                visible: rowItem.ext.isObsolete
                                implicitWidth: obsLabel.implicitWidth + 12
                                implicitHeight: 18
                                radius: 9
                                color: Theme.alpha(Theme.danger, 0.14)
                                Text { id: obsLabel; anchors.centerIn: parent; text: qsTr("Obsolete"); font.pixelSize: 10; font.weight: Font.Bold; color: Theme.danger }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignLeft
                            text: "v" + rowItem.ext.versionName + "  ·  " + page.langName(rowItem.ext.lang)
                            font.pixelSize: 12
                            font.features: { "tnum": 1 }
                            color: Theme.textFaint
                        }
                    }

                    PillButton {
                        visible: rowItem.ext.hasUpdate
                        implicitHeight: 34
                        primary: true
                        busy: rowItem.working
                        enabled: !rowItem.working
                        glyph: Icons.download
                        text: qsTr("Update")
                        onClicked: page.act(rowItem.ext, "update")
                    }
                    PillButton {
                        implicitHeight: 34
                        busy: rowItem.working && !rowItem.ext.hasUpdate
                        enabled: !rowItem.working
                        glyph: rowItem.ext.isInstalled ? Icons.trash2 : Icons.plus
                        text: rowItem.ext.isInstalled ? qsTr("Remove") : qsTr("Install")
                        onClicked: page.act(rowItem.ext, rowItem.ext.isInstalled ? "uninstall" : "install")
                    }
                }
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        visible: !page.loading && rows.count === 0
        glyph: page.view === "updates" ? Icons.circleCheck : Icons.puzzle
        title: page.view === "updates" ? qsTr("Everything is up to date")
             : page.all.length === 0 ? qsTr("The catalog is still loading") : qsTr("No matches")
        body: page.all.length === 0 ? qsTr("Revenant fetches the Keiyoushi index when the server starts.") : ""
    }

    Spinner { anchors.centerIn: parent; size: 28; visible: page.loading }
}
