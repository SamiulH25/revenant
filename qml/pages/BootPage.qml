import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Particles
import Revenant

// Shown until the extension server answers. On first run this covers the
// server download; on failure it shows the log and a retry.
Rectangle {
    id: boot

    readonly property bool failed: ServerManager.state === ServerManager.Failed
    readonly property bool downloading: ServerManager.state === ServerManager.Downloading

    color: Theme.ink

    MouseArea { anchors.fill: parent; hoverEnabled: true } // swallow input underneath

    Glow {
        // Slow-breathing light behind the mark.
        anchors.centerIn: brand
        width: 760
        height: 560
        strength: 0.12
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: boot.visible
            NumberAnimation { from: 0.4; to: 1; duration: 2200; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0.4; duration: 2200; easing.type: Easing.InOutSine }
        }
    }

    // Ghost lights rising slowly through the dark.
    ParticleSystem { id: wisps; running: boot.visible }
    ImageParticle {
        system: wisps
        source: "qrc:///particleresources/glowdot.png"
        color: Theme.alpha(Theme.accent, 0.7)
        colorVariation: 0.15
        alpha: 0.5
        entryEffect: ImageParticle.Fade
    }
    Emitter {
        system: wisps
        anchors.bottom: parent.bottom
        width: parent.width
        height: 20
        emitRate: 9
        lifeSpan: 9000
        lifeSpanVariation: 3000
        size: 16
        sizeVariation: 12
        endSize: 4
        velocity: AngleDirection { angle: 270; angleVariation: 10; magnitude: 55; magnitudeVariation: 30 }
        acceleration: PointDirection { xVariation: 8 }
    }
    Turbulence {
        system: wisps
        anchors.fill: parent
        strength: 18
    }

    ColumnLayout {
        id: brand
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 80)
        spacing: 14

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 88
            Layout.preferredHeight: 88
            Image {
                width: 88
                height: 88
                source: "qrc:/qt/qml/Revenant/assets/icons/revenant.svg"
                sourceSize: Qt.size(176, 176)
                SequentialAnimation on y {
                    // A slow hover, as ghosts do.
                    loops: Animation.Infinite
                    running: boot.visible
                    NumberAnimation { from: 0; to: -6; duration: 1800; easing.type: Easing.InOutSine }
                    NumberAnimation { from: -6; to: 0; duration: 1800; easing.type: Easing.InOutSine }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Revenant"
            font.family: Theme.display
            font.italic: true
            font.pixelSize: 72
            font.weight: Font.Medium
            font.letterSpacing: -2
            color: Theme.text
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: boot.failed ? qsTr("The extension server couldn't start") : ServerManager.statusText
            font.pixelSize: 14
            color: boot.failed ? Theme.danger : Theme.textDim
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            Layout.preferredWidth: 260
            Layout.preferredHeight: 3
            radius: 2
            color: Theme.raised
            visible: !boot.failed
            clip: true

            Rectangle {
                // Determinate: server jar download.
                visible: boot.downloading
                height: parent.height
                radius: 2
                color: Theme.accent
                width: parent.width * ServerManager.progress
                Behavior on width { NumberAnimation { duration: Theme.normal } }
            }

            Rectangle {
                // Indeterminate: probing and JVM startup.
                visible: !boot.downloading
                height: parent.height
                width: 80
                radius: 2
                color: Theme.accent
                NumberAnimation on x {
                    running: !boot.downloading && boot.visible
                    loops: Animation.Infinite
                    from: -80
                    to: 260
                    duration: 1300
                    easing.type: Easing.InOutCubic
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: boot.downloading
            text: Math.round(ServerManager.progress * 100) + "%"
            font.pixelSize: 12
            font.features: { "tnum": 1 }
            color: Theme.textFaint
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.preferredHeight: 220
            visible: boot.failed
            radius: Theme.radiusM
            color: Theme.surface
            border.color: Theme.stroke

            ScrollView {
                anchors.fill: parent
                anchors.margins: 12
                TextArea {
                    readOnly: true
                    text: ServerManager.log.slice(-40).join("\n")
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    color: Theme.textDim
                    wrapMode: TextArea.WrapAnywhere
                    background: null
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: boot.failed
            text: ServerManager.statusText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 13
            color: Theme.textDim
        }

        PillButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 6
            visible: boot.failed
            primary: true
            glyph: Icons.refreshCw
            text: qsTr("Try again")
            onClicked: ServerManager.restart()
        }
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 24
        text: qsTr("Powered by Suwayomi-Server · Extensions from Keiyoushi")
        font.pixelSize: 11
        color: Theme.textFaint
    }
}
