import QtQuick
import Revenant

// One screen at a time: single pages or two-page spreads, turned with a
// page curl (or a slide, or a fade). Turns can be dragged: grab the page,
// peel it part-way, and let go to finish or drop it back. rtl flips the
// direction for manga. currentIndex and goTo() speak in page numbers;
// internally the view steps through spreads (arrays of page indices).
Item {
    id: root

    property var pages: []
    property bool rtl: true
    property bool doublePage: false
    property bool spreadOffset: false   // first page (cover) on its own
    property string turnStyle: "curl"    // curl | slide | fade | none
    property int currentIndex: 0
    readonly property ZoomablePage currentPage: pageAt(cur)

    // Landscape pages seen so far; they always get a screen to themselves.
    property var wide: ({})
    readonly property var spreads: {
        const n = pages.length
        const out = []
        let i = 0
        if (!doublePage) {
            for (; i < n; ++i)
                out.push([i])
            return out
        }
        if (spreadOffset && n > 0) {
            out.push([0])
            i = 1
        }
        while (i < n) {
            if (wide[i] || i + 1 >= n || wide[i + 1]) {
                out.push([i])
                i += 1
            } else {
                out.push([i, i + 1])
                i += 2
            }
        }
        return out
    }

    // The spread on screen.
    property int cur: 0
    property bool relayout: false

    signal pastEnd()
    signal pastStart()
    signal toggleChrome()
    signal turned()

    function pageAt(i) {
        const slot = rep.itemAt(i)
        return slot ? slot.page : null
    }

    function spreadOf(page) {
        const i = spreads.findIndex(s => s.indexOf(page) >= 0)
        return i < 0 ? 0 : i
    }

    function setCur(i) {
        cur = i
        const spread = spreads[i]
        if (spread)
            currentIndex = spread[spread.length - 1]
        if (currentPage)
            currentPage.scrollToEdge(false)
        for (let j = 0; j < rep.count; ++j) {
            const p = pageAt(j)
            if (p && j !== i)
                p.resetZoom()
        }
    }

    function goTo(index, animate) {
        if (index < 0 || index >= pages.length)
            return
        const target = spreadOf(index)
        if (animate !== false && Math.abs(target - cur) === 1)
            startTurn(target - cur, false)
        else {
            finishNow()
            setCur(target)
        }
    }

    // --- Turning ---------------------------------------------------------------

    QtObject {
        id: turn
        property bool active: false
        property int from: 0
        property int to: 0
        property int dir: 1           // +1 forward, -1 back
        property real progress: 0     // 0 = still on `from`, 1 = arrived at `to`
        property bool manual: false   // following a drag
        property real tilt: 0.16
    }
    readonly property bool turning: turn.active
    // Exposed for scripted runs (screenshots of a turn in progress).
    property alias turnProgress: turn.progress
    property alias turnTilt: turn.tilt

    // Returns false when there's nowhere to go (and reports it).
    function startTurn(delta, manual) {
        finishNow()
        const to = cur + delta
        if (to < 0) { pastStart(); return false }
        if (to >= spreads.length) { pastEnd(); return false }
        if (turnStyle === "none" && !manual) {
            setCur(to)
            turned()
            return true
        }
        turn.from = cur
        turn.to = to
        turn.dir = delta
        turn.manual = manual
        turn.progress = 0
        if (!manual)
            turn.tilt = 0.16
        turn.active = true
        if (!manual) {
            settle.from = 0
            settle.to = 1
            settle.duration = turnStyle === "curl" ? 620 : 420
            settle.easing.type = turnStyle === "curl" ? Easing.InOutQuad : Easing.OutQuint
            settle.restart()
        }
        return true
    }

    function finishNow() {
        if (!turn.active)
            return
        settle.stop()
        if (turn.manual && turn.progress < 1) {
            turn.active = false
            return
        }
        endTurn(true)
    }

    function endTurn(arrived) {
        turn.active = false
        turn.manual = false
        if (arrived) {
            setCur(turn.to)
            turned()
        }
    }

    // Lets go of a dragged turn: finish it or drop the page back.
    function release(velocity) {
        const go = turn.progress > 0.32 || velocity > 700
        const back = velocity < -500
        settle.from = turn.progress
        settle.to = go && !back ? 1 : 0
        settle.duration = 160 + 380 * Math.abs(settle.to - turn.progress)
        settle.easing.type = Easing.OutCubic
        turn.manual = false
        settle.restart()
    }

    NumberAnimation {
        id: settle
        target: turn
        property: "progress"
        onFinished: root.endTurn(turn.progress >= 1)
    }

    function next() { startTurn(1, false) }
    function prev() { startTurn(-1, false) }

    function noteWide(page, isWide) {
        if (!doublePage || !isWide || wide[page])
            return
        const w = Object.assign({}, wide)
        w[page] = true
        wide = w
    }

    // Stay on the same page when the pairing changes (toggling spreads, or a
    // wide page turning up).
    onSpreadsChanged: {
        const page = currentIndex
        relayout = true
        finishNow()
        cur = spreadOf(page)
        relayout = false
    }
    onPagesChanged: wide = {}
    // Keyboard left/right follow the reading direction on screen.
    function stepLeft() { rtl ? next() : prev() }
    function stepRight() { rtl ? prev() : next() }
    // Space / PageDown: scroll a tall page first, then turn.
    function forward() {
        if (!(currentPage && currentPage.scrollBy(root.height * 0.8)))
            next()
    }
    function backward() {
        if (!(currentPage && currentPage.scrollBy(-root.height * 0.8)))
            prev()
    }
    function toggleZoom() {
        if (currentPage) currentPage.toggleZoom()
    }

    // --- Slots -------------------------------------------------------------------
    // Every spread gets a slot; nearby ones keep their pages decoded so turns
    // are instant. Only the current spread (and, mid-turn, its neighbour)
    // is shown.

    // Which way "forward" moves on screen.
    readonly property int screenDir: rtl ? -1 : 1

    Repeater {
        id: rep
        model: root.spreads
        delegate: Item {
            id: slot
            required property var modelData
            required property int index
            readonly property ZoomablePage page: loader.item as ZoomablePage
            readonly property bool isFrom: turn.active && index === turn.from
            readonly property bool isTo: turn.active && index === turn.to
            readonly property real p: turn.progress
            readonly property bool sliding: root.turnStyle === "slide" || (root.turnStyle === "none" && turn.manual)

            width: root.width
            height: root.height
            visible: turn.active ? (isFrom || isTo) : index === root.cur
            // Slide: the incoming page travels over; going back, the outgoing
            // page slides off the top of the one beneath.
            z: !turn.active ? 1
               : sliding ? ((turn.dir > 0) === isTo ? 2 : 1)
               : root.turnStyle === "fade" ? (isTo ? 2 : 1)
               : (isTo === (turn.dir > 0) ? 1 : 2)
            x: {
                if (!turn.active || !sliding)
                    return 0
                const w = root.width * root.screenDir
                if (turn.dir > 0)
                    return isTo ? (1 - p) * w : -p * w * 0.28
                return isFrom ? p * w : -(1 - p) * w * 0.28
            }
            opacity: {
                if (!turn.active)
                    return 1
                if (root.turnStyle === "fade")
                    return isTo ? p : 1
                if (sliding) {
                    // The page underneath sits a little in shadow.
                    const under = turn.dir > 0 ? isFrom : isTo
                    return under ? 1 - 0.45 * (turn.dir > 0 ? p : 1 - p) : 1
                }
                return 1
            }

            Loader {
                id: loader
                anchors.fill: parent
                active: Math.abs(slot.index - root.cur) <= Math.max(2, Prefs.preloadPages) || slot.isTo
                sourceComponent: ZoomablePage {
                    indices: slot.modelData
                    sources: slot.modelData.map(i => root.pages[i])
                    rtl: root.rtl
                    onMeasured: (page, isWide) => root.noteWide(page, isWide)

                    PageStatus {
                        anchors.centerIn: parent
                        page: parent
                        label: slot.modelData.map(i => i + 1).join("–")
                    }
                }
            }

            Rectangle {
                // Shadow cast by a sliding page onto the one beneath.
                visible: turn.active && slot.sliding && ((turn.dir > 0) === slot.isTo)
                width: 40
                height: parent.height
                x: root.screenDir > 0 ? -width : parent.width
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: root.screenDir > 0 ? "transparent" : Qt.rgba(0, 0, 0, 0.35) }
                    GradientStop { position: 1; color: root.screenDir > 0 ? Qt.rgba(0, 0, 0, 0.35) : "transparent" }
                }
            }
        }
    }

    // --- Curl overlay --------------------------------------------------------------
    // Going forward the current page peels away; going back the previous
    // page un-peels onto the stack.
    readonly property Item curlItem: !turn.active || turnStyle !== "curl" ? null
                                    : rep.itemAt(turn.dir > 0 ? turn.from : turn.to)
    ShaderEffectSource {
        id: curlSource
        sourceItem: root.curlItem
        hideSource: root.curlItem !== null
        live: true
        visible: false
        width: root.width
        height: root.height
    }

    ShaderEffect {
        id: curl
        anchors.fill: parent
        z: 5
        visible: root.curlItem !== null
        readonly property ZoomablePage turningPage: root.curlItem ? root.curlItem.page : null
        property variant source: curlSource
        property real progress: turn.dir > 0 ? turn.progress : 1 - turn.progress
        property real dir: root.rtl ? -1 : 1
        property real tilt: turn.tilt
        property real radius: Math.max(26, (turningPage ? turningPage.pageRect.width : width) * 0.085)
        property real shadow: 0.55
        property size viewSize: Qt.size(width, height)
        property vector4d pageRect: {
            const r = turningPage ? turningPage.pageRect : Qt.rect(0, 0, width, height)
            return Qt.vector4d(r.x, r.y, r.width, r.height)
        }
        // Fade the last sliver out rather than popping it away.
        opacity: progress > 0.88 ? Math.max(0, 1 - (progress - 0.88) / 0.12) : 1
        fragmentShader: "qrc:/qt/qml/Revenant/shaders/curl.frag.qsb"
    }

    // --- Input -----------------------------------------------------------------
    Item {
        // Input layer above the pages. Its handlers grab passively (tap) or
        // only once a horizontal drag starts, so zoomed pages still pan.
        anchors.fill: parent
        z: 10

        WheelHandler {
            // Plain wheel: scroll a tall page, then turn. Throttled so one
            // flick of a free-spinning wheel doesn't skip ten pages.
            property real last: 0
            acceptedModifiers: Qt.NoModifier
            onWheel: event => {
                const dy = -event.angleDelta.y
                if (root.currentPage && root.currentPage.scrollBy(dy * 1.2))
                    return
                const now = Date.now()
                if (now - last < 280)
                    return
                last = now
                if (dy > 0) root.next()
                else if (dy < 0) root.prev()
            }
        }

        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: event => {
                if (root.currentPage)
                    root.currentPage.zoomAt(event.angleDelta.y > 0 ? 1.15 : 1 / 1.15, point.position.x, point.position.y)
            }
        }

        DragHandler {
            // Peel the page with the pointer.
            id: peel
            target: null
            enabled: !(root.currentPage && root.currentPage.zoomed)
            yAxis.enabled: false
            dragThreshold: 8
            property int want: 0
            onActiveChanged: {
                if (active) {
                    want = 0
                    return
                }
                if (turn.active && turn.manual) {
                    const v = centroid.velocity.x * root.screenDir * (want > 0 ? -1 : 1)
                    root.release(v)
                }
            }
            onTranslationChanged: {
                const dx = translation.x
                if (!turn.manual) {
                    if (Math.abs(dx) < 6 || want !== 0)
                        return
                    // Dragging against the reading direction goes forward.
                    want = dx * root.screenDir < 0 ? 1 : -1
                    if (!root.startTurn(want, true)) {
                        want = 2   // nowhere to go; ignore the rest of the drag
                        return
                    }
                    const y = centroid.pressPosition.y / Math.max(1, root.height)
                    turn.tilt = (y - 0.5) * 0.7
                }
                const along = want > 0 ? -dx * root.screenDir : dx * root.screenDir
                turn.progress = Math.max(0, Math.min(1, along / (root.width * 0.7)))
            }
        }

        TapHandler {
            // Left/right thirds turn pages (following the reading direction);
            // the middle toggles the reader chrome. Double-tap the middle to zoom.
            acceptedButtons: Qt.LeftButton
            onTapped: eventPoint => {
                const x = eventPoint.position.x / root.width
                if (x < 0.3) root.stepLeft()
                else if (x > 0.7) root.stepRight()
                else root.toggleChrome()
            }
            onDoubleTapped: eventPoint => {
                const x = eventPoint.position.x / root.width
                if (x >= 0.3 && x <= 0.7 && root.currentPage)
                    root.currentPage.toggleZoom(eventPoint.position.x, eventPoint.position.y)
            }
        }
    }

    component PageStatus: Column {
        property ZoomablePage page
        property string label
        visible: page.status !== Image.Ready
        spacing: 12
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: parent.label
            font.family: Theme.display
            font.pixelSize: 64
            font.italic: true
            color: Theme.alpha(Theme.textFaint, 0.5)
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: parent.page.status === Image.Loading
            width: 140; height: 3; radius: 2
            color: Theme.alpha(Theme.text, 0.1)
            Rectangle {
                width: parent.width * parent.parent.page.progress
                height: 3; radius: 2
                color: Theme.accent
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: parent.page.status === Image.Error
            text: qsTr("Couldn't load this page")
            color: Theme.textDim
            font.pixelSize: 13
        }
        PillButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: parent.page.status === Image.Error
            glyph: Icons.refreshCw
            text: qsTr("Retry")
            onClicked: parent.page.retry()
        }
    }
}
