import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import Revenant

ApplicationWindow {
    id: app

    width: 1440
    height: 920
    minimumWidth: 900
    minimumHeight: 640
    visible: true
    title: "Revenant"
    color: Theme.bg

    property string tab: "library"
    readonly property var tabOrder: ["library", "browse", "history", "downloads", "extensions", "settings"]
    // +1 when moving right along the tab bar, -1 when moving left.
    property int navDirection: 1
    readonly property bool serverReady: ServerManager.state === ServerManager.Ready
    property bool storeReady: false
    // Bumped whenever library membership or read state changes, so pages that
    // show that data can refresh when they come back into view.
    property int libraryRevision: 0
    // The colour of whatever the app is showing; the aurora drifts toward it.
    property color tint: Theme.accent
    // Query waiting for Discover to open and pick it up.
    property string pendingSearch: ""
    // Scratch slot for REVENANT_SCRIPT automation.
    property var dev
    readonly property alias flight: flight

    signal libraryUpdateRequested()

    function toast(message, kind) { toaster.show(message, kind) }

    // --- Download queue, shared by every page -----------------------------
    // chapterId -> queue entry, for chapter rows to show progress.
    property var downloadQueue: []
    property var downloadMap: ({})
    property bool downloaderRunning: false
    readonly property int activeDownloads: downloadQueue.length
    // mangaId, chapterIds: chapters that left the queue (finished or removed).
    signal downloadsSettled(int mangaId, var chapterIds)

    function applyDownloadStatus(status) {
        const before = downloadMap
        const next = {}
        for (const d of status.queue)
            next[d.chapter.id] = d
        const gone = {}
        for (const id in before) {
            if (!next[id]) {
                const m = before[id].chapter.mangaId
                ;(gone[m] = gone[m] || []).push(Number(id))
            }
        }
        downloadQueue = status.queue
        downloadMap = next
        downloaderRunning = status.state === "STARTED"
        for (const m in gone)
            downloadsSettled(Number(m), gone[m])
    }

    function refreshDownloads() {
        Api.downloadStatus((error, status) => { if (!error) applyDownloadStatus(status) })
    }

    function download(chapterIds) {
        if (!chapterIds.length)
            return
        Api.enqueueDownloads(chapterIds, (error, status) => {
            if (error)
                return toast(error, "error")
            applyDownloadStatus(status)
            toast(Api.count(chapterIds.length, qsTr("Queued %1 chapter"), qsTr("Queued %1 chapters")))
        })
    }

    Timer {
        // Fast while something is downloading, lazy otherwise.
        interval: app.activeDownloads ? 1000 : 5000
        running: app.serverReady
        repeat: true
        triggeredOnStart: true
        onTriggered: app.refreshDownloads()
    }

    // --- Navigation -------------------------------------------------------

    function goTab(key) {
        if (tab === key && stack.depth === 1)
            return
        navDirection = tabOrder.indexOf(key) >= tabOrder.indexOf(tab) ? 1 : -1
        tab = key
        tint = Theme.accent
        stack.replace(null, pageFor(key), {})
    }

    function pageFor(key) {
        switch (key) {
        case "browse": return browsePage
        case "history": return historyPage
        case "extensions": return extensionsPage
        case "downloads": return downloadsPage
        case "settings": return settingsPage
        default: return libraryPage
        }
    }

    function openSource(source, query) {
        stack.push(sourcePage, { source: source, initialQuery: query || "" })
    }

    // Opens Discover and searches every source.
    function discover(query) {
        if (tab === "browse" && stack.depth === 1 && stack.currentItem.runGlobalSearch) {
            stack.currentItem.runGlobalSearch(query)
            return
        }
        pendingSearch = query
        goTab("browse")
    }

    // origin: the cover Item the title was opened from, for the flight.
    function openManga(manga, origin) {
        peek.close()
        let flying = false
        if (origin && origin.visible && manga.thumbnailUrl) {
            const r = origin.mapToItem(app.contentItem, 0, 0, origin.width, origin.height)
            flight.launch(Api.mangaCover(manga), r, Theme.radiusM)
            flying = true
        }
        stack.push(mangaPage, { mangaId: manga.id, seed: manga, origin: origin || null, flying: flying })
    }

    function peekManga(manga, origin) {
        peek.show(manga, origin)
    }

    // --- Trackers ---------------------------------------------------------
    property int pendingTrackerId: -1
    signal trackersChanged()

    function loginTracker(tracker) {
        if (!tracker.authUrl)
            return trackerLogin.openFor(tracker)
        const redirect = OAuth.redirectUrl()
        if (!redirect)
            return toast(qsTr("Couldn't open a local port for sign-in"), "error")
        pendingTrackerId = tracker.id
        // Suwayomi's registered redirect forwards to redirectUrl from the state.
        const state = { redirectUrl: redirect, clientName: "Revenant", trackerId: tracker.id, trackerName: tracker.name }
        Qt.openUrlExternally(tracker.authUrl + "&state=" + encodeURIComponent(JSON.stringify(state)))
        toast(qsTr("Finish signing in to %1 in your browser").arg(tracker.name))
    }

    Connections {
        target: OAuth
        function onReceived(callbackUrl) {
            const id = app.pendingTrackerId
            if (id < 0)
                return
            app.pendingTrackerId = -1
            Api.loginTrackerOAuth(id, callbackUrl, function (error, ok) {
                if (error || !ok)
                    return app.toast(error || qsTr("Sign-in failed"), "error")
                app.toast(qsTr("Tracker connected"))
                app.trackersChanged()
            })
        }
    }

    function openTracking(manga) {
        tracking.openFor(manga)
    }

    function editMangaCategories(manga) {
        mangaCategories.openFor(manga)
    }

    function openSourceSettings(source) {
        sourceSettings.load(source)
    }

    function openReader(manga, chapter, chapters) {
        peek.close()
        reader.active = true
        reader.item.open(manga, chapter, chapters)
    }

    function back() {
        if (reader.active) {
            reader.item.close()
            return true
        }
        if (peek.opened) {
            peek.close()
            return true
        }
        if (stack.depth > 1) {
            const page = stack.currentItem
            if (page && page.flyBack)
                page.flyBack()
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

    Timer { id: retryStore; interval: 60000; onTriggered: app.bootstrapStore() }

    Connections {
        target: ServerManager
        function onReady() { app.bootstrapStore() }
    }

    Shortcut { sequences: [StandardKey.Back, "Alt+Left", "Backspace"]; enabled: !reader.active && !palette.opened; onActivated: app.back() }
    Shortcut { sequence: "Esc"; enabled: !reader.active && peek.opened; onActivated: peek.close() }
    Shortcut { sequence: "Ctrl+1"; onActivated: app.goTab("library") }
    Shortcut { sequence: "Ctrl+2"; onActivated: app.goTab("browse") }
    Shortcut { sequence: "Ctrl+3"; onActivated: app.goTab("history") }
    Shortcut { sequence: "Ctrl+4"; onActivated: app.goTab("downloads") }
    Shortcut { sequence: "Ctrl+5"; onActivated: app.goTab("extensions") }
    Shortcut { sequence: "Ctrl+,"; onActivated: app.goTab("settings") }
    Shortcut { sequences: ["Ctrl+K", "/"]; enabled: app.serverReady && !reader.active; onActivated: palette.openWith("") }
    Shortcut { sequence: "F11"; onActivated: app.visibility = app.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }

    MouseArea {
        // Mouse "back" button anywhere in the shell.
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onClicked: app.back()
        z: -1
    }

    // --- Scene --------------------------------------------------------------

    Item {
        // Everything behind the palette, so it can blur as one while the
        // palette is open.
        id: shell
        anchors.fill: parent
        property real blurAmount: palette.opened ? 1 : 0
        Behavior on blurAmount { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
        layer.enabled: blurAmount > 0.01
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: shell.blurAmount
            blurMax: 48
            brightness: -0.15 * shell.blurAmount
            saturation: -0.2 * shell.blurAmount
        }

    Item {
        id: scene
        anchors.fill: parent
        visible: app.serverReady
        enabled: !reader.active

        Aurora {
            anchors.fill: parent
            tint: app.tint
        }

        StackView {
            id: stack
            anchors.fill: parent
            initialItem: libraryPage

            // Tabs slide in from the side they sit on in the bar.
            replaceEnter: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.slow; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "x"; from: 70 * app.navDirection; to: 0; duration: Theme.slower; easing.type: Easing.OutQuint }
                }
            }
            replaceExit: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.normal; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "x"; from: 0; to: -50 * app.navDirection; duration: Theme.normal; easing.type: Easing.InCubic }
                }
            }
            // Drilling in rises gently; the cover flight carries the eye.
            pushEnter: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.slow; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale"; from: 1.03; to: 1; duration: Theme.slower; easing.type: Easing.OutQuint }
                }
            }
            pushExit: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.normal }
                    NumberAnimation { property: "scale"; from: 1; to: 0.97; duration: Theme.slow; easing.type: Easing.OutCubic }
                }
            }
            popEnter: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.slow; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: Theme.slower; easing.type: Easing.OutQuint }
                }
            }
            popExit: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.normal }
                    NumberAnimation { property: "scale"; from: 1; to: 1.03; duration: Theme.normal; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    TopBar {
        anchors.left: parent.left
        anchors.right: parent.right
        visible: app.serverReady
        enabled: !reader.active
        backdrop: scene
        current: app.tab
        downloadBadge: app.activeDownloads
        scrolled: !!(stack.currentItem && stack.currentItem.scrolled)
        onNavigate: key => app.goTab(key)
        onOpenSearch: palette.openWith("")
        z: 10
    }
    }

    Component { id: libraryPage; LibraryPage {} }
    Component { id: browsePage; BrowsePage {} }
    Component { id: historyPage; HistoryPage {} }
    Component { id: extensionsPage; ExtensionsPage {} }
    Component { id: settingsPage; SettingsPage {} }
    Component { id: downloadsPage; DownloadsPage {} }
    Component { id: sourcePage; SourcePage {} }
    Component { id: mangaPage; MangaPage {} }

    PeekDrawer {
        id: peek
        backdrop: scene
        z: 20
    }

    CoverFlight {
        id: flight
        anchors.fill: parent
        z: 30
    }

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
        Behavior on opacity { NumberAnimation { duration: Theme.slower; easing.type: Easing.OutCubic } }
    }

    CommandPalette {
        id: palette
        onSearchEverywhere: text => app.discover(text)
        onOpenSourceRequested: source => { app.goTab("browse"); app.openSource(source) }
        onUpdateLibraryRequested: { app.goTab("library"); app.libraryUpdateRequested() }
    }

    SourceSettingsSheet { id: sourceSettings }
    MangaCategoriesSheet { id: mangaCategories }
    TrackingSheet { id: tracking }
    TrackerLoginSheet { id: trackerLogin; onSignedIn: app.trackersChanged() }

    Toast { id: toaster }
}
