import QtQuick
import Revenant

// Horizontal one-screen-at-a-time reader: single pages or two-page spreads.
// rtl flips direction for manga. currentIndex and goTo() speak in page
// numbers; the list itself holds spreads (arrays of page indices).
Item {
    id: root

    property var pages: []
    property bool rtl: true
    property bool doublePage: false
    property bool spreadOffset: false   // first page (cover) on its own
    property int currentIndex: 0
    readonly property ZoomablePage currentPage: list.currentItem as ZoomablePage

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
    property bool relayout: false

    signal pastEnd()
    signal pastStart()
    signal toggleChrome()

    function spreadOf(page) {
        const i = spreads.findIndex(s => s.indexOf(page) >= 0)
        return i < 0 ? 0 : i
    }

    function goTo(index, animate) {
        if (index < 0 || index >= pages.length)
            return
        list.highlightMoveDuration = animate === false ? 0 : 240
        list.currentIndex = spreadOf(index)
    }
    function next() {
        if (list.currentIndex >= spreads.length - 1) pastEnd()
        else {
            list.highlightMoveDuration = 240
            list.currentIndex += 1
        }
    }
    function prev() {
        if (list.currentIndex <= 0) pastStart()
        else {
            list.highlightMoveDuration = 240
            list.currentIndex -= 1
        }
    }

    function noteWide(page, isWide) {
        if (!doublePage || !isWide || wide[page])
            return
        const w = Object.assign({}, wide)
        w[page] = true
        wide = w
    }

    // The model is swapped by hand so the reader stays on the same page when
    // the pairing changes (toggling spreads, or a wide page turning up).
    onSpreadsChanged: {
        const page = currentIndex
        relayout = true
        list.model = spreads
        list.highlightMoveDuration = 0
        list.currentIndex = spreadOf(page)
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

    ListView {
        id: list
        anchors.fill: parent
        orientation: ListView.Horizontal
        layoutDirection: root.rtl ? Qt.RightToLeft : Qt.LeftToRight
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 240
        boundsBehavior: Flickable.StopAtBounds
        // Keep neighbours decoded so turning is instant.
        cacheBuffer: Math.max(0, width * Prefs.preloadPages)
        reuseItems: false
        Component.onCompleted: model = root.spreads
        interactive: !(root.currentPage && root.currentPage.zoomed)

        onCurrentIndexChanged: {
            if (root.relayout || currentIndex < 0 || currentIndex >= root.spreads.length)
                return
            // Progress counts the last page on screen.
            const spread = root.spreads[currentIndex]
            root.currentIndex = spread[spread.length - 1]
            if (root.currentPage)
                root.currentPage.scrollToEdge(false)
        }

        delegate: ZoomablePage {
            id: pageItem
            required property var modelData
            required property int index
            width: list.width
            height: list.height
            indices: modelData
            sources: modelData.map(i => root.pages[i])
            rtl: root.rtl
            onMeasured: (page, isWide) => root.noteWide(page, isWide)

            ListView.onIsCurrentItemChanged: if (!ListView.isCurrentItem) resetZoom()

            PageStatus {
                anchors.centerIn: parent
                page: pageItem
                label: pageItem.modelData.map(i => i + 1).join("–")
            }
        }
    }

    Item {
        // Input layer above the list. Its handlers only grab passively (tap)
        // or consume wheel events, so drags still reach the list for swiping
        // and panning.
        anchors.fill: parent

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
