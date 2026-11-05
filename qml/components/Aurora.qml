import QtQuick
import Revenant

// Slow, drifting pools of coloured light behind every page. The tint follows
// whatever the app is looking at, so the room takes on a title's colour.
Item {
    id: aurora

    property color tint: Theme.accent
    property real strength: 1.0

    readonly property color second: Theme.mix(tint, "#7A5CFF", 0.55)
    readonly property color third: Theme.mix(tint, "#FF7AB6", 0.35)

    clip: true

    component Drift: Glow {
        id: g
        property real cx: 0.5
        property real cy: 0.5
        property real dx: 0.1
        property real dy: 0.08
        property int period: 20000
        property real offset: 0
        property real phase: 0
        width: aurora.width * 0.9
        height: width * 0.75
        x: aurora.width * (cx + dx * Math.sin((phase + offset) * Math.PI * 2)) - width / 2
        y: aurora.height * (cy + dy * Math.cos((phase + offset) * Math.PI * 2)) - height / 2
        NumberAnimation on phase {
            from: 0; to: 1
            duration: g.period
            loops: Animation.Infinite
        }
        Behavior on color { ColorAnimation { duration: Theme.cinematic * 1.5; easing.type: Easing.InOutQuad } }
    }

    Drift { cx: 0.18; cy: 0.05; period: 26000; color: aurora.tint; strength: 0.11 * aurora.strength }
    Drift { cx: 0.85; cy: 0.12; dx: 0.08; period: 33000; offset: 0.4; color: aurora.second; strength: 0.07 * aurora.strength }
    Drift { cx: 0.6; cy: 0.95; dy: 0.05; period: 29000; offset: 0.7; color: aurora.third; strength: 0.05 * aurora.strength }
}
