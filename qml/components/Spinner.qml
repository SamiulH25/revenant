import QtQuick
import Revenant

// Ring spinner drawn as a rotating lucide loader glyph.
Icon {
    id: spinner
    property bool running: visible

    glyph: Icons.loaderCircle
    color: Theme.accent
    RotationAnimator on rotation {
        running: spinner.running
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
    }
}
