import QtQuick
import QtQuick.Effects
import Revenant

// Frosted glass: blurs whatever `backdrop` draws behind this item, tints it,
// and lights the top edge. The backdrop must not contain this item.
Item {
    id: glass

    property Item backdrop
    property real radius: 0
    property color tint: Theme.glass
    property real blur: 1.0
    property int blurMax: 48
    property real saturation: 0.25
    property bool live: true
    property bool edge: true
    property color edgeColor: Theme.glassEdge
    // Extra source captured around the panel so the blur has real pixels to
    // pull in at the edges instead of fading to black.
    readonly property int pad: blurMax

    // Re-capture after the panel moves (mapToItem has no change signal).
    function refresh() { snap.sourceRect = glass.captureRect() }
    function captureRect() {
        if (!backdrop)
            return Qt.rect(0, 0, 0, 0)
        const r = glass.mapToItem(backdrop, -pad, -pad, width + pad * 2, height + pad * 2)
        return Qt.rect(r.x, r.y, r.width, r.height)
    }
    onWidthChanged: refresh()
    onHeightChanged: refresh()
    onXChanged: refresh()
    onYChanged: refresh()
    onBackdropChanged: refresh()
    Component.onCompleted: refresh()

    ShaderEffectSource {
        id: snap
        sourceItem: glass.backdrop
        live: glass.live && glass.visible && glass.opacity > 0
        recursive: false
        visible: false
        width: glass.width + glass.pad * 2
        height: glass.height + glass.pad * 2
    }

    Item {
        id: frost
        anchors.fill: parent
        clip: true
        visible: !!glass.backdrop
        layer.enabled: glass.radius > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        MultiEffect {
            x: -glass.pad
            y: -glass.pad
            width: snap.width
            height: snap.height
            source: snap
            blurEnabled: true
            blur: glass.blur
            blurMax: glass.blurMax
            saturation: glass.saturation
            autoPaddingEnabled: false
        }
    }

    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle { anchors.fill: parent; radius: glass.radius }
    }

    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        color: glass.tint
        border.width: glass.edge ? 1 : 0
        border.color: glass.edgeColor
    }

    Rectangle {
        // Catch-light along the top edge.
        visible: glass.edge
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 0.5
        width: parent.width - glass.radius * 2
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: Theme.glassHighlight }
            GradientStop { position: 1; color: "transparent" }
        }
    }
}
