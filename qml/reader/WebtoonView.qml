import QtQuick
import QtQuick.Controls.Basic
import Revenant

// Continuous vertical strip for webtoons and long-strip manhwa.
Item {
    id: root

    property var pages: []
    property int currentIndex: 0
    property bool hasNextChapter: false
    readonly property real stripWidth: Math.min(width, Prefs.webtoonWidth)

    // Aspect ratios of pages already seen, so delegates that get recreated
    // while scrolling back come back at their real height (no jumps).
    property var ratios: ({})

    signal pastEnd()
    signal pastStart()
    signal toggleChrome()

    function goTo(index, animate) {
        if (index < 0 || index >= pages.length)
            return
        scroller.stop()
        list.positionViewAtIndex(index, ListView.Beginning)
    }
    function scrollBy(dy) {
        const max = list.contentHeight + list.originY - list.height
        const target = Math.max(list.originY, Math.min(max, list.contentY + dy))
        if (Math.abs(target - list.contentY) < 1) {
            if (dy > 0) pastEnd()
            else pastStart()
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
    function toggleZoom() {}

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
        model: root.pages
        spacing: Prefs.webtoonGap
        cacheBuffer: Math.max(height * Prefs.preloadPages, 1200)
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2600
        maximumFlickVelocity: 5200
        reuseItems: false
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // Page under the upper third of the screen counts as current.
        onContentYChanged: {
            const i = indexAt(width / 2, contentY + height / 3)
            if (i >= 0)
                root.currentIndex = i
        }

        delegate: Item {
            id: strip
            required property string modelData
            required property int index
            property int retries: 0
            readonly property url url: retries ? modelData + "?retry=" + retries : modelData

            // Strips taller than a GPU texture can hold are re-read as
            // horizontal tiles (sourceClipRect), each within the limit.
            readonly property int maxTexture: 8192
            readonly property int tileHeight: 4096
            property bool tiled: false
            property size scaled: Qt.size(0, 0)   // decoded size at strip width
            readonly property bool ready: tiled || img.status === Image.Ready

            width: list.width
            height: scaled.height > 0
                    ? Math.round(root.stripWidth * scaled.height / Math.max(1, scaled.width))
                    : Math.round(root.stripWidth * (root.ratios[index] || 1.45))

            Image {
                id: img
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.stripWidth
                height: parent.height
                visible: !strip.tiled
                source: strip.tiled ? "" : strip.url
                asynchronous: true
                smooth: true
                mipmap: true
                // Decode at display width to keep memory in check.
                sourceSize.width: Math.round(root.stripWidth * Screen.devicePixelRatio)
                fillMode: Image.Stretch
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                onStatusChanged: {
                    if (status !== Image.Ready)
                        return
                    strip.scaled = Qt.size(implicitWidth, implicitHeight)
                    root.ratios[strip.index] = implicitHeight / Math.max(1, implicitWidth)
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
                        source: strip.url
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
                visible: !strip.ready
                spacing: 12
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: strip.index + 1
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
                    Rectangle { width: parent.width * img.progress; height: 3; radius: 2; color: Theme.accent }
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

        footer: Item {
            width: list.width
            height: 260
            Column {
                anchors.centerIn: parent
                spacing: 14
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.hasNextChapter ? qsTr("End of chapter") : qsTr("You're all caught up")
                    font.family: Theme.display
                    font.pixelSize: 24
                    font.italic: true
                    color: Theme.textDim
                }
                PillButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.hasNextChapter
                    primary: true
                    glyph: Icons.skipForward
                    text: qsTr("Next chapter")
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
        }
    }
}
