import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
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
    property string transition: ""     // "" | "next" | "prev" — end-of-chapter card
    property int lastSavedPage: -1
    property bool lastSavedRead: false

    readonly property int chapterIndex: chapter ? chapters.findIndex(c => c.id === chapter.id) : -1
    readonly property var nextChapter: chapterIndex > 0 ? chapters[chapterIndex - 1] : null
    readonly property var prevChapter: chapterIndex >= 0 && chapterIndex < chapters.length - 1 ? chapters[chapterIndex + 1] : null
    readonly property bool paged: mode !== "webtoon"
    readonly property Item view: viewLoader.item

    signal closed()

    color: Prefs.readerBackground === "white" ? "#F4F2EE" : Prefs.readerBackground === "gray" ? "#232327" : "#000000"
    focus: true

    function open(m, ch, chs) {
        manga = m
        chapters = chs
        forceActiveFocus()
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
        transition = "next"
        saveProgress()
        showChrome()
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

    onCurrentPageChanged: {
        if (transition)
            transition = ""
        saveTimer.restart()
    }

    Timer { id: saveTimer; interval: 900; onTriggered: reader.saveProgress() }
    Timer {
        id: hideTimer
        interval: 2600
        onTriggered: if (!topHover.hovered && !bottomHover.hovered && !reader.loading && !reader.transition) reader.chromeVisible = false
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
        case Qt.Key_Home: if (v) v.goTo(0); break
        case Qt.Key_End: if (v) v.goTo(reader.pages.length - 1); break
        case Qt.Key_BracketRight: case Qt.Key_N: reader.goNextChapter(); break
        case Qt.Key_BracketLeft: case Qt.Key_P: reader.goPrevChapter(false); break
        case Qt.Key_M: reader.cycleMode(); break
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

    // --- Pages ---------------------------------------------------------------

    Loader {
        id: viewLoader
        anchors.fill: parent
        sourceComponent: reader.paged ? pagedComponent : webtoonComponent
    }

    Component {
        id: pagedComponent
        PagedView {
            pages: reader.pages
            doublePage: Prefs.readerDoublePage
            spreadOffset: Prefs.readerSpreadOffset
            rtl: reader.mode === "paged-rtl"
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
            onCurrentIndexChanged: reader.currentPage = currentIndex
            onPastEnd: reader.nextChapter ? reader.goNextChapter() : reader.onPastEnd()
            onPastStart: reader.onPastStart()
            onToggleChrome: reader.chromeVisible ? (reader.chromeVisible = false) : reader.showChrome()
        }
    }

    // Loading / error state for the whole chapter.
    Column {
        anchors.centerIn: parent
        spacing: 16
        visible: reader.loading || reader.error.length > 0
        Spinner { anchors.horizontalCenter: parent.horizontalCenter; size: 30; visible: reader.loading }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: reader.loading ? (reader.chapter ? reader.chapter.name : "") : qsTr("This chapter couldn't be opened")
            font.family: Theme.display
            font.pixelSize: 22
            color: Theme.text
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

    // --- End-of-chapter card ------------------------------------------------

    Rectangle {
        id: card
        readonly property var target: reader.transition === "next" ? reader.nextChapter : reader.prevChapter
        anchors.centerIn: parent
        width: 440
        height: cardCol.implicitHeight + 56
        radius: Theme.radiusXL
        color: Theme.alpha(Theme.overlay, 0.96)
        border.color: Theme.strokeStrong
        visible: opacity > 0
        opacity: reader.transition ? 1 : 0
        scale: reader.transition ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }

        ColumnLayout {
            id: cardCol
            anchors.centerIn: parent
            width: parent.width - 56
            spacing: 6

            Text {
                text: (reader.transition === "next" ? qsTr("Finished") : qsTr("Start of")).toUpperCase()
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 2
                color: Theme.accent
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
                text: card.target
                      ? (reader.transition === "next" ? qsTr("Next") : qsTr("Previous")).toUpperCase()
                      : ""
                visible: text.length > 0
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 2
                color: Theme.textFaint
            }
            Text {
                Layout.fillWidth: true
                text: card.target ? card.target.name
                    : reader.transition === "next" ? qsTr("You're all caught up.") : qsTr("This is the first chapter.")
                elide: Text.ElideRight
                wrapMode: card.target ? Text.NoWrap : Text.WordWrap
                font.pixelSize: 16
                color: card.target ? Theme.text : Theme.textDim
            }
            RowLayout {
                Layout.topMargin: 16
                spacing: 10
                PillButton {
                    visible: card.target !== null
                    primary: true
                    glyph: reader.transition === "next" ? Icons.skipForward : Icons.skipBack
                    text: reader.transition === "next" ? qsTr("Continue") : qsTr("Go back")
                    onClicked: reader.transition === "next" ? reader.goNextChapter() : reader.goPrevChapter(true)
                }
                PillButton {
                    text: card.target ? qsTr("Stay") : qsTr("Close reader")
                    onClicked: card.target ? (reader.transition = "") : reader.close()
                }
            }
        }
    }

    // --- Chrome --------------------------------------------------------------

    Item {
        id: chrome
        anchors.fill: parent
        opacity: reader.chromeVisible ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

        Rectangle {
            id: topBar
            anchors.left: parent.left
            anchors.right: parent.right
            height: 92
            y: reader.chromeVisible ? 0 : -24
            Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.82) }
                GradientStop { position: 1; color: "transparent" }
            }
            HoverHandler { id: topHover; onHoveredChanged: if (hovered) reader.showChrome(); else hideTimer.restart() }

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12

                IconButton { glyph: Icons.arrowLeft; tip: qsTr("Close (Esc)"); onClicked: reader.close() }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: reader.manga ? reader.manga.title : ""
                        elide: Text.ElideRight
                        font.pixelSize: 12
                        color: Theme.textDim
                    }
                    Text {
                        Layout.fillWidth: true
                        text: reader.chapter ? reader.chapter.name : ""
                        elide: Text.ElideRight
                        font.family: Theme.display
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        color: Theme.text
                    }
                }
                Segmented {
                    value: reader.mode
                    model: [
                        { value: "paged-rtl", label: qsTr("Manga"), glyph: Icons.arrowLeft },
                        { value: "paged-ltr", label: qsTr("Comic"), glyph: Icons.arrowRight },
                        { value: "webtoon", label: qsTr("Webtoon"), glyph: Icons.rows3 }
                    ]
                    onActivated: v => reader.setMode(v)
                }
                IconButton {
                    visible: reader.paged
                    glyph: Icons.bookOpenText
                    checkable: true
                    checked: Prefs.readerDoublePage
                    tip: Prefs.readerDoublePage ? qsTr("Single pages (2)") : qsTr("Two-page spreads (2)")
                    onClicked: Prefs.readerDoublePage = checked
                }
                IconButton {
                    visible: reader.paged && Prefs.readerDoublePage
                    glyph: Icons.flipHorizontal
                    checkable: true
                    checked: !Prefs.readerSpreadOffset
                    tip: qsTr("Shift spreads by one page (O)")
                    onClicked: Prefs.readerSpreadOffset = !Prefs.readerSpreadOffset
                }
                IconButton {
                    visible: reader.paged
                    glyph: Prefs.readerFit === "width" ? Icons.moveHorizontal : Prefs.readerFit === "original" ? Icons.zoomIn : Icons.moveVertical
                    tip: Prefs.readerFit === "width" ? qsTr("Fit width") : Prefs.readerFit === "original" ? qsTr("Original size") : qsTr("Fit screen")
                    onClicked: Prefs.readerFit = Prefs.readerFit === "height" ? "width" : Prefs.readerFit === "width" ? "original" : "height"
                }
                IconButton {
                    glyph: app.visibility === Window.FullScreen ? Icons.minimize : Icons.maximize
                    tip: qsTr("Fullscreen (F)")
                    onClicked: reader.toggleFullscreen()
                }
            }
        }

        Rectangle {
            id: bottomBar
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height - (reader.chromeVisible ? 24 : 0)
            Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            width: Math.min(parent.width - 48, 760)
            height: 60
            radius: 30
            color: Theme.alpha(Theme.overlay, 0.94)
            border.color: Theme.strokeStrong
            visible: reader.pages.length > 0
            HoverHandler { id: bottomHover; onHoveredChanged: if (hovered) reader.showChrome(); else hideTimer.restart() }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10
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
                    text: reader.currentPage + 1
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: Theme.text
                    Layout.preferredWidth: 28
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
                    background: Rectangle {
                        x: pageSlider.leftPadding
                        y: pageSlider.topPadding + pageSlider.availableHeight / 2 - 2
                        width: pageSlider.availableWidth
                        height: 4
                        radius: 2
                        color: Theme.alpha(Theme.text, 0.12)
                        Rectangle {
                            // Fill from the reading-direction start to the handle.
                            x: pageSlider.mirrored ? parent.width - width : 0
                            width: pageSlider.position * parent.width
                            height: 4
                            radius: 2
                            color: Theme.accent
                        }
                    }
                    handle: Rectangle {
                        x: pageSlider.leftPadding + pageSlider.visualPosition * (pageSlider.availableWidth - width)
                        y: pageSlider.topPadding + pageSlider.availableHeight / 2 - height / 2
                        width: pageSlider.pressed ? 18 : 14
                        height: width
                        radius: width / 2
                        color: Theme.text
                        Behavior on width { NumberAnimation { duration: Theme.fast } }
                    }
                    ToolTip {
                        parent: pageSlider.handle
                        visible: pageSlider.pressed
                        text: qsTr("Page %1").arg(Math.round(pageSlider.value) + 1)
                    }
                }
                Text {
                    text: reader.pages.length
                    font.pixelSize: 13
                    font.features: { "tnum": 1 }
                    color: Theme.textDim
                    Layout.preferredWidth: 28
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

    // Quiet page counter while the chrome is hidden.
    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 14
        visible: !reader.chromeVisible && reader.pages.length > 0
        text: (reader.currentPage + 1) + " / " + reader.pages.length
        font.pixelSize: 11
        font.features: { "tnum": 1 }
        color: Prefs.readerBackground === "white" ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(1, 1, 1, 0.4)
        style: Text.Outline
        styleColor: Prefs.readerBackground === "white" ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(0, 0, 0, 0.6)
    }
}
