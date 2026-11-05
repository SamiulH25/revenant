import QtQuick
import QtQuick.Effects
import Revenant

// Shared-element transition: a cover that lifts off one page and lands on
// another. launch() parks it over the origin; land() flies it to the target
// once the next page knows where its cover sits.
Item {
    id: flight

    property bool busy: false
    signal landed()

    function launch(source, rect, radius) {
        anim.stop()
        art.source = source
        art.radius = radius === undefined ? Theme.radiusM : radius
        place(rect)
        busy = true
        // If nobody lands it, don't leave a stray cover on screen.
        bail.restart()
    }

    function land(rect, radius) {
        if (!busy)
            return
        bail.stop()
        toX.to = rect.x
        toY.to = rect.y
        toW.to = rect.width
        toH.to = rect.height
        toR.to = radius === undefined ? Theme.radiusL : radius
        anim.restart()
    }

    function fly(source, from, to, radiusFrom, radiusTo) {
        launch(source, from, radiusFrom)
        land(to, radiusTo)
    }

    function place(rect) {
        frame.x = rect.x
        frame.y = rect.y
        frame.width = rect.width
        frame.height = rect.height
    }

    Timer { id: bail; interval: 1200; onTriggered: flight.busy = false }

    Item {
        id: frame
        visible: flight.busy

        RectangularShadow {
            anchors.fill: parent
            radius: art.radius
            blur: 48
            offset.y: 26
            color: Qt.rgba(0, 0, 0, 0.6)
        }
        Cover {
            id: art
            anchors.fill: parent
            decodeWidth: 512
        }
    }

    ParallelAnimation {
        id: anim
        // x eases in and out while y decelerates, so the path bows slightly.
        NumberAnimation { id: toX; target: frame; property: "x"; duration: Theme.slower; easing.type: Easing.InOutCubic }
        NumberAnimation { id: toY; target: frame; property: "y"; duration: Theme.slower; easing.type: Easing.OutQuint }
        NumberAnimation { id: toW; target: frame; property: "width"; duration: Theme.slower; easing.type: Easing.OutQuint }
        NumberAnimation { id: toH; target: frame; property: "height"; duration: Theme.slower; easing.type: Easing.OutQuint }
        NumberAnimation { id: toR; target: art; property: "radius"; duration: Theme.slower }
        onFinished: {
            flight.busy = false
            flight.landed()
        }
    }
}
