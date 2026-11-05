import QtQuick
import QtQuick.Controls.Basic
import Revenant

// Continuous vertical strip for webtoons and long-strip manhwa. Chapters
// join end to end: as the reader nears the bottom, the next chapter is
// appended below a divider, so a whole series reads as one scroll.
//
// segments: [{ chapter, pages: [url] }] in reading order. The view reports
// where the reader is with position(chapterId, page), and asks for more
// with nearEnd() when the last chapter is almost done.
Item {
    id: root

    property var segments: []
    property var currentChapterId: null
    // Page within the current chapter, as last reported.
    property int currentIndex: 0
    // A further chapter exists after the last segment.
    property bool hasMore: false
    property bool loadingMore: false
    property color tint: Theme.accent
    // Hands-free reading: drift down at `speed` pixels per second.
    property bool autoscroll: false
    property real speed: Prefs.autoscrollSpeed
    // Fill the window instead of the preferred strip width (Z).
    property bool fill: false
    readonly property real stripWidth: fill ? width : Math.min(width, Prefs.webtoonWidth)

    // Aspect ratios of pages already seen, keyed by URL, so delegates that
    // get recreated while scrolling come back at their real height.
    property var ratios: ({})

    signal position(var chapterId, int page)
    signal nearEnd()
    signal pastEnd()
    signal pastStart()
    signal toggleChrome()

    ListModel { id: items }

    // --- Model -------------------------------------------------------------
    // Segments only ever grow at the end or drop from the front, so the model
    // is patched rather than rebuilt (rebuilding would lose the scroll spot).
    property var built: []   // chapter ids currently in the model, in order

    onSegmentsChanged: sync()
    Component.onCompleted: sync()

    function sync() {
        const ids = segments.map(s => s.chapter.id)
        // Same strip if it still ends where ours does (it may have grown, or
        // lost chapters off the front); anything else starts afresh.
        const continues = built.length > 0 && ids.length > 0
            && ids.indexOf(built[built.length - 1]) >= 0 && built.indexOf(ids[0]) >= 0
        if (!continues) {
            items.clear()
            built = []
        }
        // Drop chapters trimmed off the front.
        while (built.length && built[0] !== ids[0])
            dropFirst()
        for (const seg of segments) {
            if (built.indexOf(seg.chapter.id) >= 0)
                continue
            if (items.count > 0)
                items.append({ kind: "divider", chapterId: seg.chapter.id, page: -1, url: "",
                               title: seg.chapter.name, previous: built.length ? chapterName(built[built.length - 1]) : "" })
            seg.pages.forEach((url, i) => items.append({ kind: "page", chapterId: seg.chapter.id, page: i, url: url, title: "", previous: "" }))
            built = built.concat([seg.chapter.id])
        }
    }

    function chapterName(id) {
        const s = segments.find(x => x.chapter.id === id)
        return s ? s.chapter.name : ""
    }

    function dropFirst() {
        const gone = built[0]
        let n = 0
        while (n < items.count && (items.get(n).chapterId === gone || (n === 0 && items.get(n).kind === "divider")))
            n++
        // The divider in front of the next chapter now leads the strip; drop it too.
        if (n < items.count && items.get(n).kind === "divider")
            n++
        if (n)
            items.remove(0, n)
        built = built.slice(1)
    }

    function indexOf(chapterId, page) {
        for (let i = 0; i < items.count; ++i) {
            const it = items.get(i)
            if (it.kind === "page" && it.chapterId === chapterId && it.page === page)
                return i
        }
        return -1
    }

    // --- Navigation ---------------------------------------------------------------

    function goTo(index, animate) {
        const i = indexOf(currentChapterId, index)
        if (i < 0)
            return
        scroller.stop()
        list.positionViewAtIndex(i, ListView.Beginning)
    }
    function scrollBy(dy) {
        const max = list.contentHeight + list.originY - list.height
        const target = Math.max(list.originY, Math.min(max, list.contentY + dy))
        if (Math.abs(target - list.contentY) < 1) {
            if (dy > 0 && !hasMore) pastEnd()
            else if (dy < 0) pastStart()
            return
        }
        scroller.to = target
        scroller.restart()
    }
    function next() { scrollBy(root.height * 0.85) }
    function prev() { scrollBy(-root.height * 0.85) }
    function forward() { next() }
    function backward() { prev() }
    function stepLeft() { prev() }
    function stepRight() { next() }
    function toggleZoom() { fill = !fill }

    FrameAnimation {
        running: root.autoscroll && root.visible && items.count > 0
        onTriggered: {
            if (list.dragging || list.flicking || scroller.running)
                return
            const max = list.contentHeight + list.originY - list.height
            if (list.contentY >= max - 0.5) {
                if (!root.hasMore)
                    root.pastEnd()
                return
            }
            list.contentY = Math.min(max, list.contentY + root.speed * frameTime)
        }
    }

    NumberAnimation {
        id: scroller
        target: list
        property: "contentY"
        duration: 260
        easing.type: Easing.OutCubic
    }

    ListView {
        id: list
        anchors.fill: parent
        model: items
        spacing: Prefs.webtoonGap
        cacheBuffer: Math.max(height * Prefs.preloadPages, 2400)
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2600
        maximumFlickVelocity: 5200
        reuseItems: false
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        property int lastReported: -1

        onContentYChanged: {
            // The page under the upper third of the screen counts as current.
            const i = indexAt(width / 2, contentY + height / 3)
            if (i >= 0 && i !== lastReported) {
                const it = items.get(i)
                if (it.kind === "page") {
                    lastReported = i
                    root.position(it.chapterId, it.page)
                }
            }
            checkNearEnd()
        }
        onContentHeightChanged: checkNearEnd()
        function checkNearEnd() {
            if (root.hasMore && !root.loadingMore && count > 0 && contentY + height > contentHeight + originY - height * 3)
                Qt.callLater(root.nearEnd)
        }
        Connections {
            target: root
            function onHasMoreChanged() { list.checkNearEnd() }
            function onLoadingMoreChanged() { list.checkNearEnd() }
        }
        onCountChanged: lastReported = -1

        delegate: Item {
            id: cell
            required property string kind
            required property var chapterId
            required property int page
            required property string url
            required property string title
            required property string previous
            required property int index

            width: list.width
            height: kind === "divider" ? 380 : strip.height

            // --- Chapter divider ---
            Column {
                visible: cell.kind === "divider"
                anchors.centerIn: parent
                spacing: 14
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    visible: cell.previous.length > 0
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20; radius: 10
                        color: Theme.alpha(root.tint, 0.2)
                        Icon { anchors.centerIn: parent; glyph: Icons.check; size: 12; color: Qt.lighter(root.tint, 1.3) }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Finished %1").arg(cell.previous)
                        font.pixelSize: 13
                        color: Theme.textDim
                    }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 180; height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: Theme.alpha(root.tint, 0.7) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("UP NEXT")
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2.4
                    color: Qt.lighter(root.tint, 1.3)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(root.stripWidth, 640)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: cell.title
                    font.family: Theme.display
                    font.pixelSize: 40
                    font.weight: Font.Medium
                    font.letterSpacing: -0.8
                    color: Theme.text
                    style: Text.Outline
                    styleColor: Qt.rgba(0, 0, 0, 0.35)
                }
            }

            // --- Page ---
            Item {
                id: strip
                visible: cell.kind === "page"
                width: parent.width
                property int retries: 0
                readonly property url src: cell.kind !== "page" ? "" : retries ? cell.url + "?retry=" + retries : cell.url

                // Strips taller than a GPU texture can hold are re-read as
                // horizontal tiles (sourceClipRect), each within the limit.
                readonly property int maxTexture: 8192
                readonly property int tileHeight: 4096
                property bool tiled: false
                property size scaled: Qt.size(0, 0)   // decoded size at strip width
                readonly property bool ready: tiled || img.status === Image.Ready

                height: cell.kind !== "page" ? 0
                        : scaled.height > 0 ? Math.round(root.stripWidth * scaled.height / Math.max(1, scaled.width))
                        : Math.round(root.stripWidth * (root.ratios[cell.url] || 1.45))

                Image {
                    id: img
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.stripWidth
                    height: parent.height
                    visible: !strip.tiled
                    source: strip.tiled ? "" : strip.src
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    // Decode at display width to keep memory in check.
                    sourceSize.width: Math.round(Math.min(root.width, Math.max(Prefs.webtoonWidth, root.stripWidth)) * Screen.devicePixelRatio)
                    fillMode: Image.Stretch
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    onStatusChanged: {
                        if (status !== Image.Ready)
                            return
                        strip.scaled = Qt.size(implicitWidth, implicitHeight)
                        root.ratios[cell.url] = implicitHeight / Math.max(1, implicitWidth)
                        if (implicitHeight > strip.maxTexture)
                            strip.tiled = true
                    }
                }

                Column {
                    visible: strip.tiled
                    anchors.horizontalCenter: parent.horizontalCenter
                    Repeater {
                        model: strip.tiled ? Math.ceil(strip.scaled.height / strip.tileHeight) : 0
                        Image {
                            required property int index
                            readonly property real clipH: Math.min(strip.tileHeight, strip.scaled.height - index * strip.tileHeight)
                            width: root.stripWidth
                            height: clipH * root.stripWidth / Math.max(1, strip.scaled.width)
                            source: strip.src
                            asynchronous: true
                            smooth: true
                            sourceSize.width: strip.scaled.width
                            sourceClipRect: Qt.rect(0, index * strip.tileHeight, strip.scaled.width, clipH)
                            fillMode: Image.Stretch
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    visible: cell.kind === "page" && !strip.ready
                    spacing: 12
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: cell.page + 1
                        font.family: Theme.display
                        font.pixelSize: 56
                        font.italic: true
                        color: Theme.alpha(Theme.textFaint, 0.5)
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: img.status === Image.Loading
                        width: 140; height: 3; radius: 2
                        color: Theme.alpha(Theme.text, 0.1)
                        Rectangle { width: parent.width * img.progress; height: 3; radius: 2; color: root.tint }
                    }
                    PillButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: img.status === Image.Error
                        glyph: Icons.refreshCw
                        text: qsTr("Retry page")
                        onClicked: strip.retries++
                    }
                }
            }
        }

        footer: Item {
            width: list.width
            height: 300
            Column {
                anchors.centerIn: parent
                spacing: 14
                Spinner {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.hasMore
                    size: 26
                    color: root.tint
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.hasMore ? qsTr("Loading the next chapter…") : qsTr("You're all caught up")
                    font.family: Theme.display
                    font.pixelSize: 26
                    font.italic: true
                    color: Theme.textDim
                }
                PillButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !root.hasMore
                    primary: true
                    glyph: Icons.check
                    text: qsTr("Finish")
                    onClicked: root.pastEnd()
                }
            }
        }
    }

    Item {
        // Input layer above the list; the tap grab is passive, so drags and
        // wheel scrolling still reach the list.
        anchors.fill: parent
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: eventPoint => {
                const x = eventPoint.position.x / root.width
                const y = eventPoint.position.y / root.height
                if (x > 0.3 && x < 0.7 && y > 0.25 && y < 0.75)
                    root.toggleChrome()
            }
            onDoubleTapped: root.toggleZoom()
        }
        WheelHandler {
            // Ctrl+wheel widens or narrows the strip.
            acceptedModifiers: Qt.ControlModifier
            onWheel: event => {
                root.fill = false
                Prefs.webtoonWidth = Math.max(360, Math.min(Math.round(root.width), Prefs.webtoonWidth + (event.angleDelta.y > 0 ? 60 : -60)))
            }
        }
    }
}
