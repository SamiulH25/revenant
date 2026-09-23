import QtQuick
import QtQuick.Shapes
import Revenant

// Soft radial light: colour at the centre fading to nothing at the edge.
Shape {
    id: glow

    property color color: Theme.accent
    property real strength: 0.18

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: -1
        fillGradient: RadialGradient {
            centerX: glow.width / 2
            centerY: glow.height / 2
            centerRadius: Math.min(glow.width, glow.height) / 2
            focalX: centerX
            focalY: centerY
            GradientStop { position: 0; color: Theme.alpha(glow.color, glow.strength) }
            GradientStop { position: 0.45; color: Theme.alpha(glow.color, glow.strength * 0.45) }
            GradientStop { position: 1; color: Theme.alpha(glow.color, 0) }
        }
        startX: 0; startY: 0
        PathLine { x: glow.width; y: 0 }
        PathLine { x: glow.width; y: glow.height }
        PathLine { x: 0; y: glow.height }
        PathLine { x: 0; y: 0 }
    }
}
