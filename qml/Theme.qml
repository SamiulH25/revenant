pragma Singleton
import QtQuick

QtObject {
    // Surfaces, darkest to lightest.
    readonly property color ink: "#060609"
    readonly property color bg: "#0A0A0F"
    readonly property color surface: "#111118"
    readonly property color raised: "#18181F"
    readonly property color overlay: "#1F1F28"
    readonly property color hover: Qt.rgba(1, 1, 1, 0.05)
    readonly property color pressed: Qt.rgba(1, 1, 1, 0.09)
    readonly property color stroke: Qt.rgba(1, 1, 1, 0.07)
    readonly property color strokeStrong: Qt.rgba(1, 1, 1, 0.14)

    // Frosted glass: translucent fill over a blurred backdrop, with a bright
    // hairline on top where light catches the edge.
    readonly property color glass: Qt.rgba(16 / 255, 16 / 255, 23 / 255, 0.58)
    readonly property color glassStrong: Qt.rgba(20 / 255, 20 / 255, 28 / 255, 0.82)
    readonly property color glassEdge: Qt.rgba(1, 1, 1, 0.09)
    readonly property color glassHighlight: Qt.rgba(1, 1, 1, 0.16)

    readonly property color text: "#F1EEF6"
    readonly property color textDim: "#A9A5B6"
    readonly property color textFaint: "#6D6A7B"

    // Ecto-mint: the app's single accent. Manga pages swap in a colour
    // lifted from the cover (see Ambient.qml).
    readonly property color accent: "#8BE9CF"
    readonly property color accentInk: "#07130F"
    readonly property color accentDeep: "#2E8C74"
    readonly property color danger: "#FF6F7D"
    readonly property color warning: "#FFC46B"
    readonly property color nsfw: "#FF8FB1"

    readonly property string display: "Fraunces"
    readonly property string ui: "Inter"
    readonly property string icons: "lucide"

    readonly property int radiusS: 6
    readonly property int radiusM: 10
    readonly property int radiusL: 16
    readonly property int radiusXL: 24

    // Motion. Entrances decelerate hard (OutQuint); exits are quick.
    readonly property int fast: 140
    readonly property int normal: 240
    readonly property int slow: 420
    readonly property int slower: 680
    readonly property int cinematic: 1100
    // Delay between items in a staggered entrance.
    readonly property int stagger: 34

    readonly property int gutter: 40
    readonly property int navHeight: 72
    readonly property int contentTop: 96
    // Kept for pages that still lay out against a side rail.
    readonly property int navWidth: 0

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }
    function luminance(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    // Text colour that reads on top of c.
    function onColor(c) { return luminance(c) > 0.55 ? "#0B0B10" : "#FFFFFF" }
    // Lifts dark cover colours so they still glow against the near-black UI.
    function vivid(c) {
        const l = luminance(c)
        return l < 0.35 ? mix(c, "#FFFFFF", (0.35 - l) * 1.4) : c
    }
}
