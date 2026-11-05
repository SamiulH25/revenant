import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Particles
import Revenant

Rectangle {
    id: reader

    property var manga
    property var chapters: []          // newest first
    property var chapter
    property var pages: []
    property int currentPage: 0
    property bool loading: false
    property string error
    property string mode: Prefs.readerMode
    property bool chromeVisible: true
    property string transition: ""     // "" | "next" | "prev": end-of-chapter cards
    property int lastSavedPage: -1
    property bool lastSavedRead: false
    property color tint: Theme.accent
    // Hands-free: paged modes turn every few seconds, webtoon scrolls.
    property bool autoplay: false
    // For the chapter-complete card.
    property real chapterStartedAt: 0
    property int furthestPage: 0

    readonly property int chapterIndex: chapter ? chapters.findIndex(c => c.id === chapter.id) : -1
    readonly property var nextChapter: chapterIndex > 0 ? chapters[chapterIndex - 1] : null
    readonly property var prevChapter: chapterIndex >= 0 && chapterIndex < chapters.length - 1 ? chapters[chapterIndex + 1] : null
    readonly property bool paged: mode !== "webtoon"
    readonly property Item view: viewLoader.item
    readonly property int readInSeries: chapters.filter(c => c.isRead).length
    readonly property bool lightPaper: Prefs.readerBackground === "white"

    signal closed()

    color: Prefs.readerBackground === "white" ? "#F4F2EE" : Prefs.readerBackground === "gray" ? "#232327" : "#000000"
    focus: true

    function open(m, ch, chs) {
        manga = m
        chapters = chs
        if (m && m.thumbnailUrl)
            ImageCache.accent(Api.coverKey(m.thumbnailUrl, m.thumbnailUrlLastFetched), c => { if (c) reader.tint = Theme.vivid(c) })
        forceActiveFocus()
        entrance.restart()
        loadChapter(ch, false)
    }

    function close() {
        saveProgress()
        closed()
    }

    function loadChapter(ch, fromEnd) {
        saveProgress()
        chapter = ch
        transition = ""
        pages = []
        error = ""
        loading = true
        lastSavedPage = -1
        lastSavedRead = ch.isRead
        chapterStartedAt = Date.now()
        furthestPage = 0
        const requested = ch.id
        Api.pages(ch.id, function (err, result) {
            if (!chapter || chapter.id !== requested)
                return
            loading = false
            if (err) {
                error = err
                return
            }
            const base = ServerManager.baseUrl.toString()
            patchChapter(result.chapter)
            pages = result.pages.map(p => base + p)
            const start = fromEnd ? pages.length - 1
                        : ch.isRead ? 0
                        : Math.max(0, Math.min(ch.lastPageRead, pages.length - 1))
            currentPage = start
            lastSavedPage = start
            furthestPage = start
            Qt.callLater(() => { if (view) view.goTo(start, false) })
            showChrome()
        })
    }

    // Merge fresh fields for one chapter into the local list.
    function patchChapter(fields) {
        chapters = chapters.map(c => c.id === fields.id ? Object.assign({}, c, fields) : c)
        if (chapter && chapter.id === fields.id)
            chapter = Object.assign({}, chapter, fields)
    }

    function saveProgress() {
        if (!chapter || pages.length === 0)
            return
        const atEnd = currentPage >= pages.length - 1
        const markRead = Prefs.autoMarkRead && atEnd && !lastSavedRead
        if (currentPage === lastSavedPage && !markRead)
            return
        const patch = { lastPageRead: currentPage }
        if (markRead)
            patch.isRead = true
        lastSavedPage = currentPage
        if (markRead)
            lastSavedRead = true
        const id = chapter.id
        Api.updateChapters([id], patch, function (err) {
            if (err)
                return app.toast(qsTr("Couldn't save progress: %1").arg(err), "error")
            patchChapter(Object.assign({ id: id }, patch))
            if (patch.isRead && reader.manga)
                Api.trackProgress(reader.manga.id)
        })
    }

    function goNextChapter() {
        if (nextChapter)
            loadChapter(nextChapter, false)
    }
    function goPrevChapter(fromEnd) {
        if (prevChapter)
            loadChapter(prevChapter, fromEnd === true)
    }

    function onPastEnd() {
        if (transition === "next") {
            if (nextChapter) goNextChapter()
            return
        }
        // Webtoon autoscroll flows straight on into the next chapter.
        if (!paged && autoplay && nextChapter) {
            goNextChapter()
            return
        }
        autoplay = false
        transition = "next"
        saveProgress()
        showChrome()
        finale.celebrate()
    }
    function onPastStart() {
        if (transition === "prev") {
            if (prevChapter) goPrevChapter(true)
            return
        }
        transition = "prev"
        showChrome()
    }

    function setMode(next) {
        const page = currentPage
        mode = next
        Prefs.readerMode = next
        Qt.callLater(() => { if (view) view.goTo(page, false) })
    }
    function cycleMode() {
        const modes = ["paged-rtl", "paged-ltr", "webtoon"]
        setMode(modes[(modes.indexOf(mode) + 1) % modes.length])
    }

    function showChrome() {
        chromeVisible = true
        hideTimer.restart()
    }
    function toggleFullscreen() {
        app.visibility = app.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen
    }

    function toggleChapters() {
        showChrome()
        chapterMenu.opened ? chapterMenu.close() : chapterMenu.open()
    }
    function toggleSettings() {
        showChrome()
        settingsMenu.opened ? settingsMenu.close() : settingsMenu.open()
    }

    function toggleAutoplay() {
        autoplay = !autoplay
        hint.show(autoplay ? (paged ? qsTr("Autoplay · a page every %1 s").arg(Prefs.autoplaySeconds)
                                    : qsTr("Autoscroll · %1 px/s").arg(Prefs.autoscrollSpeed))
                           : qsTr("Autoplay off"), autoplay ? Icons.play : Icons.pause)
    }
    function adjustAutoplay(faster) {
        if (paged) {
            Prefs.autoplaySeconds = Math.max(2, Math.min(30, Prefs.autoplaySeconds + (faster ? -1 : 1)))
            hint.show(qsTr("A page every %1 s").arg(Prefs.autoplaySeconds), faster ? Icons.fastForward : Icons.rewind)
            autoTurn.restart()
        } else {
            Prefs.autoscrollSpeed = Math.max(20, Math.min(600, Prefs.autoscrollSpeed + (faster ? 20 : -20)))
            hint.show(qsTr("Autoscroll · %1 px/s").arg(Prefs.autoscrollSpeed), faster ? Icons.fastForward : Icons.rewind)
        }
    }

    onCurrentPageChanged: {
        if (transition)
            transition = ""
        furthestPage = Math.max(furthestPage, currentPage)
        saveTimer.restart()
        if (autoplay)
            autoTurn.restart()
    }

    Timer { id: saveTimer; interval: 900; onTriggered: reader.saveProgress() }
    Timer {
        id: hideTimer
        interval: 2600
        onTriggered: if (!topHover.hovered && !bottomHover.hovered && !reader.loading && !reader.transition
                         && !chapterMenu.opened && !settingsMenu.opened) reader.chromeVisible = false
    }
    Timer {
        id: autoTurn
        interval: Prefs.autoplaySeconds * 1000
        repeat: true
        running: reader.autoplay && reader.paged && !reader.transition && !reader.loading
        onTriggered: if (reader.view) reader.view.forward()
    }

    HoverHandler {
        id: pointer
        cursorShape: reader.chromeVisible ? Qt.ArrowCursor : Qt.BlankCursor
        onPointChanged: {
            // Reveal the chrome when the pointer nears the top or bottom edge.
            const y = point.position.y
            if (y < 90 || y > reader.height - 110)
                reader.showChrome()
        }
    }

    Keys.onPressed: event => {
        const v = reader.view
        switch (event.key) {
        case Qt.Key_Left: case Qt.Key_A: if (v) v.stepLeft(); break
        case Qt.Key_Right: case Qt.Key_D: if (v) v.stepRight(); break
        case Qt.Key_Space:
            if (v) (event.modifiers & Qt.ShiftModifier) ? v.backward() : v.forward()
            break
        case Qt.Key_Down: case Qt.Key_PageDown: case Qt.Key_S: if (v) v.forward(); break
        case Qt.Key_Up: case Qt.Key_PageUp: case Qt.Key_W: if (v) v.backward(); break
        case Qt.Key_Home: if (v) v.goTo(0, false); break
        case Qt.Key_End: if (v) v.goTo(reader.pages.length - 1, false); break
        case Qt.Key_BracketRight: case Qt.Key_N: reader.goNextChapter(); break
        case Qt.Key_BracketLeft: case Qt.Key_P: reader.goPrevChapter(false); break
        case Qt.Key_M: reader.cycleMode(); break
        case Qt.Key_K: reader.toggleAutoplay(); break
        case Qt.Key_C: reader.toggleChapters(); break
        case Qt.Key_Comma: reader.toggleSettings(); break
        case Qt.Key_J: reader.adjustAutoplay(false); break
        case Qt.Key_L: reader.adjustAutoplay(true); break
        case Qt.Key_2: if (reader.paged) Prefs.readerDoublePage = !Prefs.readerDoublePage; break
        case Qt.Key_O: if (reader.paged && Prefs.readerDoublePage) Prefs.readerSpreadOffset = !Prefs.readerSpreadOffset; break
        case Qt.Key_Z: if (v) v.toggleZoom(); break
        case Qt.Key_F: case Qt.Key_F11: reader.toggleFullscreen(); break
        case Qt.Key_H: case Qt.Key_Tab:
            reader.chromeVisible = !reader.chromeVisible
            if (reader.chromeVisible) hideTimer.restart()
            break
        case Qt.Key_Return: case Qt.Key_Enter:
            if (reader.transition === "next") reader.goNextChapter()
            else if (reader.transition === "prev") reader.goPrevChapter(true)
            break
        case Qt.Key_Escape: case Qt.Key_Backspace: case Qt.Key_Q:
            if (reader.transition) reader.transition = ""
            else reader.close()
            break
        default:
            return
        }
        event.accepted = true
    }

    // --- Stage: ambient light and the pages ------------------------------------

    Item {
        id: stage
        anchors.fill: parent

        Item {
            // The current page, blurred huge behind itself, so the margins
            // glow with whatever is on the page, tinted by the series.
            anchors.fill: parent
            visible: Prefs.readerBackground === "ambient"
            Backdrop {
                anchors.fill: parent
                source: reader.pages.length ? reader.pages[Math.min(reader.currentPage, reader.pages.length - 1)] : ""
                tint: reader.tint
                intensity: 0.42
                wash: 0.14
                sideShade: false
                fade: false
            }
            Rectangle {
                // Vignette.
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
                    GradientStop { position: 0.3; color: Qt.rgba(0, 0, 0, 0.1) }
                    GradientStop { position: 0.7; color: Qt.rgba(0, 0, 0, 0.1) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) }
                }
            }
        }

        Loader {
            id: viewLoader
            anchors.fill: parent
            sourceComponent: reader.paged ? pagedComponent : webtoonComponent
        }
    }

    Component {
        id: pagedComponent
        PagedView {
            pages: reader.pages
            doublePage: Prefs.readerDoublePage
            spreadOffset: Prefs.readerSpreadOffset
            rtl: reader.mode === "paged-rtl"
            turnStyle: Prefs.readerTurn
            onCurrentIndexChanged: reader.currentPage = currentIndex
            onPastEnd: reader.onPastEnd()
            onPastStart: reader.onPastStart()
            onToggleChrome: reader.chromeVisible ? (reader.chromeVisible = false) : reader.showChrome()
        }
    }

    Component {
        id: webtoonComponent
        WebtoonView {
            pages: reader.pages
            hasNextChapter: reader.nextChapter !== null
            autoscroll: reader.autoplay && !reader.transition
            onCurrentIndexChanged: reader.currentPage = currentIndex
            onPastEnd: reader.nextChapter && !reader.autoplay ? reader.goNextChapter() : reader.onPastEnd()
            onPastStart: reader.onPastStart()
            onToggleChrome: reader.chromeVisible ? (reader.chromeVisible = false) : reader.showChrome()
        }
    }

    // Loading / error state for the whole chapter.
    Column {
        anchors.centerIn: parent
        spacing: 16
        visible: reader.loading || reader.error.length > 0
        Spinner { anchors.horizontalCenter: parent.horizontalCenter; size: 30; visible: reader.loading; color: reader.tint }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: reader.loading ? (reader.chapter ? reader.chapter.name : "") : qsTr("This chapter couldn't be opened")
            font.family: Theme.display
            font.pixelSize: 26
            color: reader.lightPaper ? "#111" : Theme.text
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(520, reader.width - 80)
            visible: reader.error.length > 0
            text: reader.error
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: Theme.textDim
            font.pixelSize: 13
        }
        PillButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: reader.error.length > 0
            primary: true
            glyph: Icons.refreshCw
            text: qsTr("Try again")
            onClicked: reader.loadChapter(reader.chapter, false)
        }
    }

    // --- Chapter complete ---------------------------------------------------------

    Item {
        id: finale
        anchors.fill: parent
        visible: opacity > 0
        opacity: reader.transition === "next" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }

        readonly property bool caughtUp: !reader.nextChapter
        readonly property int minutes: Math.max(1, Math.round((Date.now() - reader.chapterStartedAt) / 60000))

        function celebrate() {
            burst.burst(finale.caughtUp ? 140 : 70)
            pop.restart()
        }

        MouseArea { anchors.fill: parent; enabled: finale.visible; onClicked: reader.transition = "" }

        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.9 }
        Backdrop {
            anchors.fill: parent
            source: reader.manga ? Api.mangaCover(reader.manga) : ""
            tint: reader.tint
            intensity: 0.8
            sideShade: false
            fade: false
            wash: 0.16
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }

        ParticleSystem { id: wisps; running: finale.visible }
        ImageParticle {
            system: wisps
            source: "qrc:///particleresources/glowdot.png"
            color: Theme.alpha(reader.tint, 0.85)
            colorVariation: 0.25
            alpha: 0.6
            entryEffect: ImageParticle.Fade
        }
        Emitter {
            // Ghost lights drifting up the whole time the card is open.
            system: wisps
            anchors.bottom: parent.bottom
            width: parent.width
            height: 10
            emitRate: finale.visible ? 14 : 0
            lifeSpan: 5200
            lifeSpanVariation: 1500
            size: 18
            sizeVariation: 14
            endSize: 2
            velocity: AngleDirection { angle: 270; angleVariation: 18; magnitude: 70; magnitudeVariation: 40 }
            acceleration: PointDirection { xVariation: 12 }
        }
        Emitter {
            // The burst when a chapter is finished.
            id: burst
            system: wisps
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -140
            width: 10; height: 10
            enabled: false
            lifeSpan: 1900
            lifeSpanVariation: 600
            size: 22
            sizeVariation: 16
            endSize: 0
            velocity: AngleDirection { angleVariation: 360; magnitude: 260; magnitudeVariation: 160 }
            acceleration: PointDirection { y: 140 }
        }

        ColumnLayout {
            id: finaleCard
            anchors.centerIn: parent
            width: Math.min(620, parent.width - 80)
            spacing: 0

            Rectangle {
                id: badge
                Layout.alignment: Qt.AlignHCenter
                width: 76; height: 76; radius: 38
                color: Theme.alpha(reader.tint, 0.18)
                border.color: Theme.alpha(reader.tint, 0.6)
                RectangularShadow { anchors.fill: parent; radius: 38; blur: 40; color: Theme.alpha(reader.tint, 0.55); z: -1 }
                Icon {
                    anchors.centerIn: parent
                    glyph: finale.caughtUp ? Icons.trophy : Icons.check
                    size: 34
                    color: Qt.lighter(reader.tint, 1.25)
                }
                SequentialAnimation {
                    id: pop
                    NumberAnimation { target: badge; property: "scale"; from: 0.3; to: 1.15; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                    NumberAnimation { target: badge; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 22
                text: (finale.caughtUp ? qsTr("You're all caught up") : qsTr("Chapter complete")).toUpperCase()
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.letterSpacing: 2.6
                color: Qt.lighter(reader.tint, 1.3)
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 10
                horizontalAlignment: Text.AlignHCenter
                text: reader.chapter ? reader.chapter.name : ""
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Theme.display
                font.pixelSize: 44
                font.weight: Font.Medium
                font.letterSpacing: -1
                color: Theme.text
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 22
                spacing: 10
                Repeater {
                    model: [
                        { glyph: Icons.bookOpen, text: Api.count(reader.pages.length, qsTr("%1 page"), qsTr("%1 pages")) },
                        { glyph: Icons.timer, text: qsTr("%1 min").arg(finale.minutes) },
                        { glyph: Icons.bookCopy, text: qsTr("%1 of %2 chapters").arg(Math.max(reader.readInSeries, reader.chapters.length - reader.chapterIndex)).arg(reader.chapters.length) }
                    ]
                    Rectangle {
                        required property var modelData
                        width: st.implicitWidth + 26
                        height: 34
                        radius: 17
                        color: Theme.alpha("#FFFFFF", 0.07)
                        border.color: Theme.alpha("#FFFFFF", 0.1)
                        Row {
                            id: st
                            anchors.centerIn: parent
                            spacing: 8
                            Icon { anchors.verticalCenter: parent.verticalCenter; glyph: modelData.glyph; size: 14; color: Theme.textDim }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.text; font.pixelSize: 13; color: Theme.text }
                        }
                    }
                }
            }

            Rectangle {
                // Up next.
                Layout.fillWidth: true
                Layout.topMargin: 30
                Layout.preferredHeight: 92
                visible: !finale.caughtUp
                radius: Theme.radiusL
                color: Theme.alpha(Theme.raised, 0.75)
                border.color: Theme.glassEdge
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 16
                    Cover {
                        Layout.preferredWidth: 43
                        Layout.preferredHeight: 64
                        radius: 6
                        source: reader.manga ? Api.mangaCover(reader.manga) : ""
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text { text: qsTr("UP NEXT"); font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.8; color: Theme.textFaint }
                        Text {
                            Layout.fillWidth: true
                            text: reader.nextChapter ? reader.nextChapter.name : ""
                            elide: Text.ElideRight
                            font.pixelSize: 17
                            font.weight: Font.Medium
                            color: Theme.text
                        }
                    }
                    PillButton {
                        implicitHeight: 48
                        primary: true
                        accent: reader.tint
                        glyph: Icons.skipForward
                        text: qsTr("Continue")
                        onClicked: reader.goNextChapter()
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 26
                visible: finale.caughtUp
                text: qsTr("That's every chapter there is. New ones will show up in your library.")
                font.pixelSize: 14
                color: Theme.textDim
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 22
                spacing: 10
                PillButton {
                    text: qsTr("Stay on this page")
                    onClicked: reader.transition = ""
                }
                PillButton {
                    glyph: Icons.bookOpenText
                    text: qsTr("Back to the series")
                    onClicked: reader.close()
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 18
                visible: !finale.caughtUp
                text: qsTr("Turn the page again or press Enter to keep reading")
                font.pixelSize: 12
                color: Theme.textFaint
            }
        }
    }

    // --- Start-of-chapter card --------------------------------------------------------

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 440
        height: cardCol.implicitHeight + 56
        radius: Theme.radiusXL
        color: Theme.alpha(Theme.overlay, 0.96)
        border.color: Theme.strokeStrong
        visible: opacity > 0
        opacity: reader.transition === "prev" ? 1 : 0
        scale: reader.transition === "prev" ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }

        ColumnLayout {
            id: cardCol
            anchors.centerIn: parent
            width: parent.width - 56
            spacing: 6

            Text {
                text: qsTr("Start of").toUpperCase()
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 2
                color: reader.tint
            }
            Text {
                Layout.fillWidth: true
                text: reader.chapter ? reader.chapter.name : ""
                elide: Text.ElideRight
                font.family: Theme.display
                font.pixelSize: 22
                color: Theme.text
            }
            Rectangle { Layout.fillWidth: true; Layout.topMargin: 12; Layout.bottomMargin: 12; Layout.preferredHeight: 1; color: Theme.stroke }
            Text {
                text: reader.prevChapter ? qsTr("Previous").toUpperCase() : ""
                visible: text.length > 0
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 2
                color: Theme.textFaint
            }
            Text {
                Layout.fillWidth: true
                text: reader.prevChapter ? reader.prevChapter.name : qsTr("This is the first chapter.")
                elide: Text.ElideRight
                wrapMode: reader.prevChapter ? Text.NoWrap : Text.WordWrap
                font.pixelSize: 16
                color: reader.prevChapter ? Theme.text : Theme.textDim
            }
            RowLayout {
                Layout.topMargin: 16
                spacing: 10
                PillButton {
                    visible: reader.prevChapter !== null
                    primary: true
                    accent: reader.tint
                    glyph: Icons.skipBack
                    text: qsTr("Go back")
                    onClicked: reader.goPrevChapter(true)
                }
                PillButton {
                    text: reader.prevChapter ? qsTr("Stay") : qsTr("Close reader")
                    onClicked: reader.prevChapter ? (reader.transition = "") : reader.close()
                }
            }
        }
    }

    // --- Chrome ---------------------------------------------------------------------

    Item {
        id: chrome
        anchors.fill: parent
        opacity: reader.chromeVisible ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

        Item {
            id: topBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 16
            height: 64
            y: reader.chromeVisible ? 16 : -40
            Behavior on y { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutQuint } }
            HoverHandler { id: topHover; onHoveredChanged: if (hovered) reader.showChrome(); else hideTimer.restart() }

            GlassPanel {
                anchors.fill: parent
                radius: 22
                backdrop: stage
                tint: Theme.alpha(Theme.bg, 0.62)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 12
                spacing: 12

                IconButton { glyph: Icons.arrowLeft; tip: qsTr("Close (Esc)"); onClicked: reader.close() }
                Cover {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 45
                    radius: 5
                    source: reader.manga ? Api.mangaCover(reader.manga) : ""
                }
                AbstractButton {
                    id: chapterButton
                    Layout.fillWidth: true
                    Layout.maximumWidth: 520
                    implicitHeight: 48
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: reader.toggleChapters()
                    background: Rectangle {
                        radius: 12
                        color: chapterButton.hovered || chapterMenu.opened ? Theme.hover : "transparent"
                    }
                    contentItem: ColumnLayout {
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            leftPadding: 8
                            text: reader.manga ? reader.manga.title : ""
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            color: Theme.textDim
                        }
                        RowLayout {
                            spacing: 6
                            Text {
                                Layout.maximumWidth: 460
                                leftPadding: 8
                                text: reader.chapter ? reader.chapter.name : ""
                                elide: Text.ElideRight
                                font.family: Theme.display
                                font.pixelSize: 18
                                font.weight: Font.Medium
                                color: Theme.text
                            }
                            Icon {
                                glyph: Icons.chevronDown
                                size: 14
                                color: Theme.textDim
                                rotation: chapterMenu.opened ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Theme.normal } }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }

                Rectangle {
                    // Autoplay status.
                    visible: reader.autoplay
                    implicitWidth: apRow.implicitWidth + 24
                    implicitHeight: 34
                    radius: 17
                    color: Theme.alpha(reader.tint, 0.16)
                    border.color: Theme.alpha(reader.tint, 0.45)
                    Row {
                        id: apRow
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7; height: 7; radius: 3.5
                            color: reader.tint
                            SequentialAnimation on opacity {
                                running: reader.autoplay
                                loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 0.25; duration: 700 }
                                NumberAnimation { from: 0.25; to: 1; duration: 700 }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: reader.paged ? qsTr("Autoplay · %1 s").arg(Prefs.autoplaySeconds) : qsTr("Autoscroll · %1").arg(Prefs.autoscrollSpeed)
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Theme.text
                        }
                    }
                }
                IconButton {
                    glyph: reader.autoplay ? Icons.pause : Icons.play
                    tip: reader.autoplay ? qsTr("Stop autoplay (K)") : (reader.paged ? qsTr("Autoplay pages (K · J/L speed)") : qsTr("Autoscroll (K · J/L speed)"))
                    checked: reader.autoplay
                    onClicked: reader.toggleAutoplay()
                }
                IconButton {
                    id: settingsButton
                    glyph: Icons.slidersHorizontal
                    tip: qsTr("Reading settings (,)")
                    checked: settingsMenu.opened
                    onClicked: reader.toggleSettings()
                }
                IconButton {
                    glyph: app.visibility === Window.FullScreen ? Icons.minimize : Icons.maximize
                    tip: qsTr("Fullscreen (F)")
                    onClicked: reader.toggleFullscreen()
                }
            }

            // Chapter list, dropping from the title.
            Popup {
                id: chapterMenu
                x: chapterButton.x
                y: parent.height + 10
                width: 420
                height: Math.min(460, reader.height - 140)
                padding: 8
                onOpened: chapterList.positionViewAtIndex(Math.max(0, reader.chapterIndex), ListView.Center)
                background: Rectangle { radius: 18; color: Theme.alpha(Theme.raised, 0.97); border.color: Theme.glassEdge }
                enter: Transition { ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal }
                    NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.slow; easing.type: Easing.OutBack }
                } }
                exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.fast } }
                contentItem: ListView {
                    id: chapterList
                    clip: true
                    model: reader.chapters
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    delegate: AbstractButton {
                        id: chRow
                        required property var modelData
                        required property int index
                        readonly property bool here: !!reader.chapter && modelData.id === reader.chapter.id
                        width: chapterList.width
                        height: 46
                        hoverEnabled: true
                        onClicked: { chapterMenu.close(); reader.loadChapter(modelData, false) }
                        background: Rectangle {
                            radius: 10
                            color: chRow.here ? Theme.alpha(reader.tint, 0.16) : chRow.hovered ? Theme.hover : "transparent"
                        }
                        contentItem: RowLayout {
                            spacing: 12
                            Rectangle {
                                Layout.leftMargin: 10
                                width: 6; height: 6; radius: 3
                                color: chRow.modelData.isRead ? "transparent" : reader.tint
                                border.color: chRow.modelData.isRead ? Theme.textFaint : reader.tint
                            }
                            Text {
                                Layout.fillWidth: true
                                text: chRow.modelData.name
                                elide: Text.ElideRight
                                font.pixelSize: 14
                                font.weight: chRow.here ? Font.DemiBold : Font.Normal
                                color: chRow.here ? Theme.text : chRow.modelData.isRead ? Theme.textFaint : Theme.alpha(Theme.text, 0.88)
                            }
                            Text {
                                Layout.rightMargin: 10
                                visible: chRow.here
                                text: qsTr("Reading")
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: reader.tint
                            }
                        }
                    }
                }
            }

            // Reading settings.
            Popup {
                id: settingsMenu
                x: parent.width - width
                y: parent.height + 10
                width: 400
                padding: 22
                background: Rectangle { radius: 20; color: Theme.alpha(Theme.raised, 0.97); border.color: Theme.glassEdge }
                enter: Transition { ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal }
                    NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: Theme.slow; easing.type: Easing.OutBack }
                } }
                exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.fast } }
                contentItem: ColumnLayout {
                    spacing: 18


                    ColumnLayout {
                        spacing: 8
                        SettingLabel { text: qsTr("READING MODE  ·  M") }
                        Segmented {
                            value: reader.mode
                            model: [
                                { value: "paged-rtl", label: qsTr("Manga"), glyph: Icons.arrowLeft },
                                { value: "paged-ltr", label: qsTr("Comic"), glyph: Icons.arrowRight },
                                { value: "webtoon", label: qsTr("Webtoon"), glyph: Icons.rows3 }
                            ]
                            onActivated: v => reader.setMode(v)
                        }
                    }
                    ColumnLayout {
                        visible: reader.paged
                        spacing: 8
                        SettingLabel { text: qsTr("PAGE TURN") }
                        Segmented {
                            value: Prefs.readerTurn
                            model: [
                                { value: "curl", label: qsTr("Curl") },
                                { value: "slide", label: qsTr("Slide") },
                                { value: "fade", label: qsTr("Fade") },
                                { value: "none", label: qsTr("Instant") }
                            ]
                            onActivated: v => Prefs.readerTurn = v
                        }
                    }
                    ColumnLayout {
                        visible: reader.paged
                        spacing: 8
                        SettingLabel { text: qsTr("FIT") }
                        Segmented {
                            value: Prefs.readerFit
                            model: [
                                { value: "height", label: qsTr("Screen"), glyph: Icons.moveVertical },
                                { value: "width", label: qsTr("Width"), glyph: Icons.moveHorizontal },
                                { value: "original", label: qsTr("Original"), glyph: Icons.zoomIn }
                            ]
                            onActivated: v => Prefs.readerFit = v
                        }
                    }
                    RowLayout {
                        visible: reader.paged
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { text: qsTr("Two-page spreads"); font.pixelSize: 14; color: Theme.text }
                            Text { text: qsTr("Press 2 to toggle, O to shift the pairing"); font.pixelSize: 12; color: Theme.textFaint }
                        }
                        Toggle { checked: Prefs.readerDoublePage; onToggled: Prefs.readerDoublePage = checked }
                    }
                    ColumnLayout {
                        spacing: 8
                        SettingLabel { text: qsTr("BACKGROUND") }
                        Segmented {
                            value: Prefs.readerBackground
                            model: [
                                { value: "ambient", label: qsTr("Ambient"), glyph: Icons.sparkles },
                                { value: "black", label: qsTr("Black") },
                                { value: "gray", label: qsTr("Grey") },
                                { value: "white", label: qsTr("White") }
                            ]
                            onActivated: v => Prefs.readerBackground = v
                        }
                    }
                }
            }
        }

        Item {
            id: bottomBar
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height - (reader.chromeVisible ? 22 : -30)
            Behavior on y { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutQuint } }
            width: Math.min(parent.width - 48, 820)
            height: 64
            visible: reader.pages.length > 0
            HoverHandler { id: bottomHover; onHoveredChanged: if (hovered) reader.showChrome(); else hideTimer.restart() }

            GlassPanel {
                anchors.fill: parent
                radius: 32
                backdrop: stage
                tint: Theme.alpha(Theme.bg, 0.62)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12
                // Manga reads right to left, so the whole bar mirrors.
                LayoutMirroring.enabled: reader.mode === "paged-rtl"
                LayoutMirroring.childrenInherit: true

                IconButton {
                    glyph: LayoutMirroring.enabled ? Icons.skipForward : Icons.skipBack
                    tip: qsTr("Previous chapter ([)")
                    enabled: reader.prevChapter !== null
                    onClicked: reader.goPrevChapter(false)
                }
                Text {
                    text: (reader.currentPage + 1) + " / " + reader.pages.length
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: Theme.text
                    Layout.preferredWidth: 64
                    horizontalAlignment: Text.AlignHCenter
                }
                Slider {
                    id: pageSlider
                    Layout.fillWidth: true
                    from: 0
                    to: Math.max(1, reader.pages.length - 1)
                    stepSize: 1
                    snapMode: Slider.SnapAlways
                    value: reader.currentPage
                    onMoved: if (reader.view) reader.view.goTo(Math.round(value), false)
                    // Page under the pointer, for the preview.
                    readonly property int peekPage: {
                        if (pressed)
                            return Math.round(value)
                        if (!sliderHover.hovered)
                            return -1
                        let f = (sliderHover.point.position.x - leftPadding) / Math.max(1, availableWidth)
                        if (mirrored) f = 1 - f
                        return Math.max(0, Math.min(reader.pages.length - 1, Math.round(f * (reader.pages.length - 1))))
                    }
                    HoverHandler { id: sliderHover }
                    background: Rectangle {
                        x: pageSlider.leftPadding
                        y: pageSlider.topPadding + pageSlider.availableHeight / 2 - 2
                        width: pageSlider.availableWidth
                        height: 4
                        radius: 2
                        color: Theme.alpha(Theme.text, 0.14)
                        Rectangle {
                            // Fill from the reading-direction start to the handle.
                            x: pageSlider.mirrored ? parent.width - width : 0
                            width: pageSlider.position * parent.width
                            height: 4
                            radius: 2
                            color: reader.tint
                        }
                    }
                    handle: Rectangle {
                        x: pageSlider.leftPadding + pageSlider.visualPosition * (pageSlider.availableWidth - width)
                        y: pageSlider.topPadding + pageSlider.availableHeight / 2 - height / 2
                        width: pageSlider.pressed ? 20 : sliderHover.hovered ? 16 : 13
                        height: width
                        radius: width / 2
                        color: Theme.text
                        border.color: reader.tint
                        border.width: 2
                        Behavior on width { NumberAnimation { duration: Theme.fast } }
                    }

                    Item {
                        // Thumbnail of the page under the pointer.
                        id: preview
                        visible: opacity > 0
                        opacity: pageSlider.peekPage >= 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                        width: 132
                        height: 188 + 26
                        y: -height - 22
                        x: {
                            const n = Math.max(1, reader.pages.length - 1)
                            let f = Math.max(0, pageSlider.peekPage) / n
                            if (pageSlider.mirrored) f = 1 - f
                            return pageSlider.leftPadding + f * pageSlider.availableWidth - width / 2
                        }
                        Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        RectangularShadow { anchors.fill: thumbFrame; radius: 10; blur: 24; offset.y: 10; color: Qt.rgba(0, 0, 0, 0.6) }
                        Rectangle {
                            id: thumbFrame
                            width: parent.width
                            height: 188
                            radius: 10
                            color: Theme.raised
                            border.color: Theme.glassEdge
                            clip: true
                            Image {
                                anchors.fill: parent
                                anchors.margins: 4
                                source: pageSlider.peekPage >= 0 ? reader.pages[pageSlider.peekPage] : ""
                                sourceSize.height: 360
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            text: qsTr("Page %1").arg(pageSlider.peekPage + 1)
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Theme.text
                            style: Text.Outline
                            styleColor: Qt.rgba(0, 0, 0, 0.6)
                        }
                    }
                }
                Text {
                    text: Math.round((reader.currentPage + 1) / Math.max(1, reader.pages.length) * 100) + "%"
                    font.pixelSize: 12
                    font.features: { "tnum": 1 }
                    color: Theme.textDim
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignHCenter
                }
                IconButton {
                    glyph: LayoutMirroring.enabled ? Icons.skipBack : Icons.skipForward
                    tip: qsTr("Next chapter (])")
                    enabled: reader.nextChapter !== null
                    onClicked: reader.goNextChapter()
                }
            }
        }
    }

    // Reading progress as a hairline along the bottom while the chrome hides.
    Rectangle {
        anchors.bottom: parent.bottom
        x: reader.mode === "paged-rtl" ? parent.width - width : 0
        height: 2
        width: parent.width * (reader.currentPage + 1) / Math.max(1, reader.pages.length)
        visible: !reader.chromeVisible && reader.pages.length > 0
        color: Theme.alpha(reader.tint, 0.8)
        Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
    }

    // Brief on-screen hint for keyboard actions (autoplay speed and so on).
    Rectangle {
        id: hint
        function show(text, glyph) {
            hintText.text = text
            hintIcon.glyph = glyph
            opacity = 1
            hintTimer.restart()
        }
        anchors.centerIn: parent
        width: hintRow.implicitWidth + 40
        height: 54
        radius: 27
        color: Theme.alpha(Theme.bg, 0.8)
        border.color: Theme.glassEdge
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Timer { id: hintTimer; interval: 1300; onTriggered: hint.opacity = 0 }
        Row {
            id: hintRow
            anchors.centerIn: parent
            spacing: 10
            Icon { id: hintIcon; anchors.verticalCenter: parent.verticalCenter; size: 18; color: reader.tint }
            Text { id: hintText; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 15; font.weight: Font.Medium; color: Theme.text }
        }
    }

    // The reader opens by zooming out of the dark.
    ParallelAnimation {
        id: entrance
        NumberAnimation { target: reader; property: "opacity"; from: 0; to: 1; duration: Theme.slow; easing.type: Easing.OutCubic }
        NumberAnimation { target: stage; property: "scale"; from: 1.06; to: 1; duration: Theme.slower; easing.type: Easing.OutQuint }
    }

    component SettingLabel: Text {
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 1.6
        color: Theme.textFaint
    }
}
