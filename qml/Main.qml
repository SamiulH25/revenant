import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

ApplicationWindow {
    id: app

    width: 1440
    height: 920
    minimumWidth: 800
    minimumHeight: 640
    visible: true
    title: "Revenant"
    color: Theme.bg

    property string tab: "library"
    readonly property bool serverReady: ServerManager.state === ServerManager.Ready
    property bool storeReady: false
    // Bumped whenever library membership or read state changes, so pages that
    // show that data can refresh when they come back into view.
    property int libraryRevision: 0

    function toast(message, kind) { toaster.show(message, kind) }

    function goTab(key) {
        if (tab === key && stack.depth === 1)
            return
        tab = key
        stack.replace(null, pageFor(key), {}, StackView.Immediate)
    }

    function pageFor(key) {
        switch (key) {
        case "browse": return browsePage
        case "history": return historyPage
        case "extensions": return extensionsPage
        case "settings": return settingsPage
        default: return libraryPage
        }
    }

    function openSource(source, query) {
        stack.push(sourcePage, { source: source, initialQuery: query || "" })
    }

    function openManga(manga) {
        stack.push(mangaPage, { mangaId: manga.id, seed: manga })
    }

    function openReader(manga, chapter, chapters) {
        reader.active = true
        reader.item.open(manga, chapter, chapters)
    }

    function back() {
        if (reader.active) {
            reader.item.close()
            return true
        }
        if (stack.depth > 1) {
            stack.pop()
            return true
        }
        return false
    }

    function bootstrapStore() {
        Api.bootstrap(function (error) {
            if (error) {
                toast(qsTr("Couldn't refresh the Keiyoushi index: %1").arg(error), "error")
                retryStore.start()
                return
            }
            storeReady = true
        })
    }

    Timer { id: retryStore; interval: 15000; onTriggered: app.bootstrapStore() }

    Connections {
        target: ServerManager
        function onReady() { app.bootstrapStore() }
    }

    Shortcut { sequences: [StandardKey.Back, "Alt+Left", "Backspace"]; enabled: !reader.active; onActivated: app.back() }
    Shortcut { sequence: "Ctrl+1"; onActivated: app.goTab("library") }
    Shortcut { sequence: "Ctrl+2"; onActivated: app.goTab("browse") }
    Shortcut { sequence: "Ctrl+3"; onActivated: app.goTab("history") }
    Shortcut { sequence: "Ctrl+4"; onActivated: app.goTab("extensions") }
    Shortcut { sequence: "Ctrl+,"; onActivated: app.goTab("settings") }
    Shortcut { sequence: "F11"; onActivated: app.visibility = app.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }

    MouseArea {
        // Mouse "back" button anywhere in the shell.
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onClicked: app.back()
        z: -1
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        visible: app.serverReady
        enabled: !reader.active

        NavRail {
            Layout.fillHeight: true
            current: app.tab
            onNavigate: key => app.goTab(key)
        }

        StackView {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            initialItem: libraryPage

            pushEnter: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "x"; from: 40; to: 0; duration: Theme.slow; easing.type: Easing.OutQuint }
                }
            }
            pushExit: Transition {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.fast }
            }
            popEnter: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "x"; from: -30; to: 0; duration: Theme.slow; easing.type: Easing.OutQuint }
                }
            }
            popExit: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.fast }
                    NumberAnimation { property: "x"; from: 0; to: 40; duration: Theme.normal; easing.type: Easing.OutCubic }
                }
            }
            replaceEnter: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
            }
            replaceExit: Transition {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.fast }
            }
        }
    }

    Component { id: libraryPage; LibraryPage {} }
    Component { id: browsePage; BrowsePage {} }
    Component { id: historyPage; HistoryPage {} }
    Component { id: extensionsPage; ExtensionsPage {} }
    Component { id: settingsPage; SettingsPage {} }
    Component { id: sourcePage; SourcePage {} }
    Component { id: mangaPage; MangaPage {} }

    Loader {
        id: reader
        anchors.fill: parent
        active: false
        z: 100
        sourceComponent: ReaderPage {
            onClosed: {
                app.libraryRevision++
                // Unload after the handler returns; the reader is its sender.
                Qt.callLater(() => reader.active = false)
            }
        }
    }

    BootPage {
        anchors.fill: parent
        z: 200
        visible: opacity > 0
        opacity: app.serverReady ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    }

    Toast { id: toaster }
}
