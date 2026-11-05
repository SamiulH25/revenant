import QtQuick
import Revenant

// Entrance for any item: lifts it into place `delay` ms after it's created
// (or after `active` turns true). Bind the item's opacity to `progress`:
//
//     Text { transform: Reveal { id: rv; delay: 80 } opacity: rv.progress }
Translate {
    id: r

    property int delay: 0
    property real distance: 22
    property real progress: 0
    property bool active: true
    property int duration: Theme.slower

    y: (1 - progress) * distance

    function play() { anim.restart() }

    onActiveChanged: if (active) anim.restart()
    Component.onCompleted: if (active) anim.restart()

    property SequentialAnimation anim: SequentialAnimation {
        PauseAnimation { duration: Math.max(0, r.delay) }
        NumberAnimation { target: r; property: "progress"; from: 0; to: 1; duration: r.duration; easing.type: Easing.OutQuint }
    }
}
