pragma Singleton
import QtQuick

QtObject {
    // Surfaces, darkest to lightest.
    readonly property color ink: "#08080B"
    readonly property color bg: "#0C0C11"
    readonly property color surface: "#121219"
    readonly property color raised: "#191921"
    readonly property color overlay: "#20202A"
    readonly property color hover: Qt.rgba(1, 1, 1, 0.05)
    readonly property color pressed: Qt.rgba(1, 1, 1, 0.09)
    readonly property color stroke: Qt.rgba(1, 1, 1, 0.07)
    readonly property color strokeStrong: Qt.rgba(1, 1, 1, 0.14)

    readonly property color text: "#EEEBF3"
    readonly property color textDim: "#A6A2B3"
    readonly property color textFaint: "#6B6879"

    // Ecto-mint: the app's single accent. Manga pages swap in a colour
    // lifted from the cover (see Ambient.qml).
    readonly property color accent: "#8BE9CF"
    readonly property color accentInk: "#07130F"
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

    readonly property int fast: 140
    readonly property int normal: 240
    readonly property int slow: 420

    readonly property int gutter: 32
    readonly property int navWidth: 76

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }
}
