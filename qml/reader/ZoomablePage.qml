import QtQuick
import Revenant

// One page in the paged reader: fits to the viewport per Prefs.readerFit,
// zooms (pinch here; Ctrl+wheel, Z and double-tap via PagedView) and pans
// when larger than the view.
Item {
    id: root

    property url source
    property int retries: 0
    readonly property alias status: img.status
    readonly property alias progress: img.progress
    readonly property bool zoomed: view.zoom > 1.01

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
        readonly property real natW: img.implicitWidth > 0 ? img.implicitWidth : 1
        readonly property real natH: img.implicitHeight > 0 ? img.implicitHeight : 1
        readonly property real baseScale: {
            if (Prefs.readerFit === "width")
                return width / natW
            if (Prefs.readerFit === "original")
                return 1 / Screen.devicePixelRatio
            return Math.min(width / natW, height / natH)
        }
        readonly property real shownW: natW * baseScale * zoom
        readonly property real shownH: natH * baseScale * zoom

        anchors.fill: parent
        clip: true
        contentWidth: Math.max(width, shownW)
        contentHeight: Math.max(height, shownH)
        boundsBehavior: Flickable.StopAtBounds
        // Only take drags when there's somewhere to pan; otherwise let the
        // parent ListView swipe between pages.
        interactive: shownW > width + 1 || shownH > height + 1

        Behavior on contentY { enabled: !view.moving; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Image {
            id: img
            x: (view.contentWidth - view.shownW) / 2
            y: (view.contentHeight - view.shownH) / 2
            width: view.shownW
            height: view.shownH
            source: root.retries ? root.source + "?retry=" + root.retries : root.source
            asynchronous: true
            smooth: true
            mipmap: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        }
    }

    PinchHandler {
        target: null
        onScaleChanged: delta => root.zoomAt(delta, centroid.position.x, centroid.position.y)
    }
}
