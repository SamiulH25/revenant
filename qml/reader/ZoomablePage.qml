import QtQuick
import Revenant

// One screen in the paged reader: a single page, or a two-page spread laid
// side by side at a common height. Fits to the viewport per Prefs.readerFit,
// zooms (pinch here; Ctrl+wheel, Z and double-tap via PagedView) and pans
// when larger than the view.
Item {
    id: root

    property var sources: []          // one or two page URLs, in reading order
    property var indices: []          // their page numbers (0-based)
    property bool rtl: false          // spreads read right to left
    property int retries: 0
    readonly property bool zoomed: view.zoom > 1.01

    readonly property int status: {
        let ready = 0
        for (let i = 0; i < rep.count; ++i) {
            const img = rep.itemAt(i) as Image
            if (!img) return Image.Loading
            if (img.status === Image.Error) return Image.Error
            if (img.status === Image.Ready) ++ready
        }
        return rep.count > 0 && ready === rep.count ? Image.Ready : Image.Loading
    }
    readonly property real progress: {
        let sum = 0
        for (let i = 0; i < rep.count; ++i)
            sum += rep.itemAt(i) ? (rep.itemAt(i) as Image).progress : 0
        return rep.count ? sum / rep.count : 0
    }

    // Emitted per page once its size is known; PagedView uses it to keep
    // landscape spreads on their own.
    signal measured(int pageIndex, bool wide)

    function resetZoom() {
        view.zoom = 1
        view.contentX = 0
        view.contentY = 0
    }

    // Zooms keeping the point (x, y) in page coordinates fixed.
    function zoomAt(factor, x, y) {
        const next = Math.max(1, Math.min(6, view.zoom * factor))
        const px = (view.contentX + x) / Math.max(view.contentWidth, 1)
        const py = (view.contentY + y) / Math.max(view.contentHeight, 1)
        view.zoom = next
        view.contentX = Math.max(0, Math.min(view.contentWidth - width, px * view.contentWidth - x))
        view.contentY = Math.max(0, Math.min(view.contentHeight - height, py * view.contentHeight - y))
    }

    function toggleZoom(x, y) {
        if (zoomed)
            resetZoom()
        else
            zoomAt(2.2, x === undefined ? width / 2 : x, y === undefined ? height / 2 : y)
    }

    // Scrolls within the page. Returns false when already at that edge, so
    // the caller can turn the page instead.
    function scrollBy(dy) {
        const max = view.contentHeight - height
        if (max <= 1)
            return false
        if ((dy > 0 && view.contentY >= max - 1) || (dy < 0 && view.contentY <= 1))
            return false
        view.contentY = Math.max(0, Math.min(max, view.contentY + dy))
        return true
    }

    // Jump to the top (or bottom) of a tall page when it becomes current.
    function scrollToEdge(bottom) {
        view.contentY = bottom ? Math.max(0, view.contentHeight - height) : 0
    }

    function retry() { retries++ }

    Flickable {
        id: view

        property real zoom: 1
        // Every page is scaled to the tallest one's height, then laid in a row.
        readonly property real commonH: {
            let h = 1
            for (let i = 0; i < rep.count; ++i) {
                const img = rep.itemAt(i) as Image
                if (img && img.implicitHeight > h) h = img.implicitHeight
            }
            return h
        }
        readonly property real natW: {
            let w = 0
            for (let i = 0; i < rep.count; ++i) {
                const img = rep.itemAt(i) as Image
                w += img && img.implicitHeight > 0 ? img.implicitWidth * commonH / img.implicitHeight : commonH * 0.7
            }
            return Math.max(1, w)
        }
        readonly property real natH: commonH
        readonly property real baseScale: {
            if (Prefs.readerFit === "width")
                return width / natW
            if (Prefs.readerFit === "original")
                return 1 / Screen.devicePixelRatio
            return Math.min(width / natW, height / natH)
        }
        readonly property real fitScale: baseScale * zoom
        readonly property real shownW: natW * fitScale
        readonly property real shownH: natH * fitScale

        anchors.fill: parent
        clip: true
        contentWidth: Math.max(width, shownW)
        contentHeight: Math.max(height, shownH)
        boundsBehavior: Flickable.StopAtBounds
        // Only take drags when there's somewhere to pan; otherwise let the
        // parent ListView swipe between pages.
        interactive: shownW > width + 1 || shownH > height + 1

        Behavior on contentY { enabled: !view.moving; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Row {
            x: (view.contentWidth - view.shownW) / 2
            y: (view.contentHeight - view.shownH) / 2
            layoutDirection: root.rtl ? Qt.RightToLeft : Qt.LeftToRight

            Repeater {
                id: rep
                model: root.sources
                Image {
                    required property string modelData
                    required property int index
                    width: implicitHeight > 0 ? implicitWidth * view.commonH / implicitHeight * view.fitScale : view.shownW / Math.max(1, rep.count)
                    height: view.shownH
                    source: root.retries ? modelData + "?retry=" + root.retries : modelData
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    fillMode: Image.PreserveAspectFit
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    onStatusChanged: {
                        if (status === Image.Ready && root.indices.length > index)
                            root.measured(root.indices[index], implicitWidth > implicitHeight * 1.1)
                    }
                }
            }
        }
    }

    PinchHandler {
        target: null
        onScaleChanged: delta => root.zoomAt(delta, centroid.position.x, centroid.position.y)
    }
}
