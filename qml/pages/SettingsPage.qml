import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

Item {
    id: page

    property real cacheBytes: ImageCache.diskUsage()
    // Settings stored by the extension server (downloads, library updates).
    property var server: ({})
    property var trackers: []

    function loadTrackers() {
        Api.trackers((error, list) => { if (!error) page.trackers = list })
    }

    Connections {
        target: app
        function onTrackersChanged() { page.loadTrackers() }
    }

    function setServer(patch) {
        Api.setServerSettings(patch, function (error, settings) {
            if (error)
                return app.toast(error, "error")
            page.server = settings
        })
    }

    Component.onCompleted: {
        Api.serverSettings((error, settings) => { if (!error) page.server = settings })
        loadTrackers()
    }

    readonly property var updateIntervals: [
        { value: 0, label: qsTr("Off") }, { value: 6, label: qsTr("Every 6 hours") },
        { value: 12, label: qsTr("Every 12 hours") }, { value: 24, label: qsTr("Daily") },
        { value: 48, label: qsTr("Every 2 days") }, { value: 168, label: qsTr("Weekly") }
    ]

    function formatBytes(n) {
        if (n < 1024 * 1024) return qsTr("%1 KB").arg(Math.round(n / 1024))
        if (n < 1024 * 1024 * 1024) return qsTr("%1 MB").arg((n / 1048576).toFixed(1))
        return qsTr("%1 GB").arg((n / 1073741824).toFixed(2))
    }

    component Group: ColumnLayout {
        id: group
        property string title
        default property alias rows: body.data
        Layout.fillWidth: true
        spacing: 12
        Text {
            text: group.title
            font.family: Theme.display
            font.pixelSize: 21
            font.weight: Font.Medium
            color: Theme.text
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: body.implicitHeight
            radius: Theme.radiusL
            color: Theme.surface
            border.color: Theme.stroke
            ColumnLayout {
                id: body
                width: parent.width
                spacing: 0
            }
        }
    }

    component Field: Item {
        id: field
        property string label
        property string hint
        default property alias control: slot.data
        property bool last: false
        Layout.fillWidth: true
        implicitHeight: Math.max(64, textCol.implicitHeight + 28)

        ColumnLayout {
            id: textCol
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.right: slot.left
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text { text: field.label; font.pixelSize: 14; font.weight: Font.Medium; color: Theme.text }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: field.hint
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Theme.textFaint
            }
        }
        Row {
            id: slot
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
        }
        Rectangle {
            visible: !field.last
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 20
            height: 1
            color: Theme.stroke
        }
    }

    component Range: Slider {
        id: sl
        property string suffix
        implicitWidth: 220
        background: Rectangle {
            x: sl.leftPadding
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            width: sl.availableWidth
            height: 4
            radius: 2
            color: Theme.overlay
            Rectangle { width: sl.visualPosition * parent.width; height: 4; radius: 2; color: Theme.accent }
        }
        handle: Rectangle {
            x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
            y: sl.topPadding + sl.availableHeight / 2 - height / 2
            width: 18; height: 18; radius: 9
            color: Theme.text
            border.color: Theme.accent
            border.width: sl.pressed ? 4 : 2
        }
        ToolTip.visible: pressed
        ToolTip.text: Math.round(value) + suffix
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 80
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: col
            x: Theme.gutter
            y: Theme.contentTop
            width: Math.min(parent.width - Theme.gutter * 2, 860)
            spacing: 34

            SectionHeader { eyebrow: qsTr("Preferences"); title: qsTr("Settings") }

            Group {
                title: qsTr("Reader")
                Field {
                    label: qsTr("Default reading mode")
                    hint: qsTr("Change it any time in the reader with M.")
                    Segmented {
                        value: Prefs.readerMode
                        model: [
                            { value: "paged-rtl", label: qsTr("Manga"), glyph: Icons.arrowLeft },
                            { value: "paged-ltr", label: qsTr("Comic"), glyph: Icons.arrowRight },
                            { value: "webtoon", label: qsTr("Webtoon"), glyph: Icons.rows3 }
                        ]
                        onActivated: v => Prefs.readerMode = v
                    }
                }
                Field {
                    label: qsTr("Page fit")
                    hint: qsTr("How single pages fill the window in paged modes.")
                    Segmented {
                        value: Prefs.readerFit
                        model: [
                            { value: "height", label: qsTr("Height") },
                            { value: "width", label: qsTr("Width") },
                            { value: "original", label: qsTr("Original") }
                        ]
                        onActivated: v => Prefs.readerFit = v
                    }
                }
                Field {
                    label: qsTr("Two-page spreads")
                    hint: qsTr("Show facing pages side by side in paged modes (toggle with 2 in the reader). Wide pages stay on their own.")
                    Toggle { checked: Prefs.readerDoublePage; onToggled: Prefs.readerDoublePage = checked }
                }
                Field {
                    label: qsTr("Cover page on its own")
                    hint: qsTr("Keeps spreads aligned for books that start with a single cover (O in the reader).")
                    Toggle { enabled: Prefs.readerDoublePage; checked: Prefs.readerSpreadOffset; onToggled: Prefs.readerSpreadOffset = checked }
                }
                Field {
                    label: qsTr("Webtoon width")
                    hint: qsTr("Maximum strip width. %1 px").arg(Prefs.webtoonWidth)
                    Range { from: 480; to: 1600; stepSize: 20; suffix: " px"; value: Prefs.webtoonWidth; onMoved: Prefs.webtoonWidth = value }
                }
                Field {
                    label: qsTr("Webtoon page gap")
                    hint: qsTr("%1 px between pages").arg(Prefs.webtoonGap)
                    Range { from: 0; to: 48; stepSize: 2; suffix: " px"; value: Prefs.webtoonGap; onMoved: Prefs.webtoonGap = value }
                }
                Field {
                    label: qsTr("Page turn")
                    hint: qsTr("How pages change in paged modes. Curl turns like paper; you can also drag a page to peel it.")
                    Segmented {
                        value: Prefs.readerTurn
                        model: [
                            { value: "curl", label: qsTr("Curl") },
                            { value: "slide", label: qsTr("Slide") },
                            { value: "fade", label: qsTr("Fade") },
                            { value: "none", label: qsTr("Instant") }
                        ]
                        onActivated: v => Prefs.readerTurn = v
                    }
                }
                Field {
                    label: qsTr("Background")
                    hint: qsTr("Ambient lights the margins with the colours of the page you're on.")
                    Segmented {
                        value: Prefs.readerBackground
                        model: [
                            { value: "ambient", label: qsTr("Ambient"), glyph: Icons.sparkles },
                            { value: "black", label: qsTr("Black") },
                            { value: "gray", label: qsTr("Gray") },
                            { value: "white", label: qsTr("White") }
                        ]
                        onActivated: v => Prefs.readerBackground = v
                    }
                }
                Field {
                    label: qsTr("Autoplay speed")
                    hint: qsTr("Paged modes turn a page every %1 seconds while autoplay is on (K in the reader, J and L to adjust).").arg(Prefs.autoplaySeconds)
                    Range { from: 2; to: 30; stepSize: 1; suffix: " s"; value: Prefs.autoplaySeconds; onMoved: Prefs.autoplaySeconds = value }
                }
                Field {
                    label: qsTr("Autoscroll speed")
                    hint: qsTr("Webtoon mode drifts down %1 pixels a second while autoscroll is on.").arg(Prefs.autoscrollSpeed)
                    Range { from: 20; to: 600; stepSize: 10; suffix: " px/s"; value: Prefs.autoscrollSpeed; onMoved: Prefs.autoscrollSpeed = value }
                }
                Field {
                    label: qsTr("Preload pages")
                    hint: qsTr("Pages fetched ahead of the one you're reading: %1").arg(Prefs.preloadPages)
                    Range { from: 1; to: 12; stepSize: 1; value: Prefs.preloadPages; onMoved: Prefs.preloadPages = value }
                }
                Field {
                    last: true
                    label: qsTr("Mark chapters read automatically")
                    hint: qsTr("When you reach the last page.")
                    Toggle { checked: Prefs.autoMarkRead; onToggled: Prefs.autoMarkRead = checked }
                }
            }

            Group {
                title: qsTr("Library & browsing")
                Field {
                    label: qsTr("Cover size")
                    hint: qsTr("%1 px").arg(Prefs.coverSize)
                    Range { from: 120; to: 280; stepSize: 10; suffix: " px"; value: Prefs.coverSize; onMoved: Prefs.coverSize = value }
                }
                Field {
                    last: true
                    label: qsTr("Show 18+ sources and extensions")
                    Toggle { checked: Prefs.showNsfw; onToggled: Prefs.showNsfw = checked }
                }
            }

            Group {
                title: qsTr("Downloads")
                Field {
                    label: qsTr("Save as CBZ archives")
                    hint: qsTr("One file per chapter instead of a folder of images.")
                    Toggle { checked: !!page.server.downloadAsCbz; onToggled: page.setServer({ downloadAsCbz: checked }) }
                }
                Field {
                    label: qsTr("Download new chapters automatically")
                    hint: qsTr("After a library update, for titles in your library.")
                    Toggle { checked: !!page.server.autoDownloadNewChapters; onToggled: page.setServer({ autoDownloadNewChapters: checked }) }
                }
                Field {
                    last: true
                    label: qsTr("Download location")
                    hint: page.server.downloadsPath ? page.server.downloadsPath : qsTr("Default: %1/data/downloads").arg(ServerManager.dataDir)
                    TextBox {
                        id: pathBox
                        width: 240
                        placeholderText: qsTr("Default location")
                        text: page.server.downloadsPath || ""
                        onAccepted: page.setServer({ downloadsPath: text.trim() })
                    }
                    PillButton { text: qsTr("Save"); onClicked: page.setServer({ downloadsPath: pathBox.text.trim() }) }
                }
            }

            Group {
                title: qsTr("Library updates")
                Field {
                    label: qsTr("Check for new chapters")
                    hint: qsTr("The server checks every title in your library on this schedule.")
                    Dropdown {
                        width: 200
                        model: page.updateIntervals
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: page.updateIntervals.findIndex(o => o.value === page.server.globalUpdateInterval)
                        onActivated: page.setServer({ globalUpdateInterval: currentValue })
                    }
                }
                Field {
                    label: qsTr("Skip titles with unread chapters")
                    Toggle { checked: !!page.server.excludeEntryWithUnreadChapters; onToggled: page.setServer({ excludeEntryWithUnreadChapters: checked }) }
                }
                Field {
                    last: true
                    label: qsTr("Refresh details and covers too")
                    hint: qsTr("Slower, but keeps descriptions and cover art current.")
                    Toggle { checked: !!page.server.updateMangas; onToggled: page.setServer({ updateMangas: checked }) }
                }
            }

            Group {
                title: qsTr("Tracking")
                Repeater {
                    model: page.trackers
                    Field {
                        required property var modelData
                        required property int index
                        last: index === page.trackers.length - 1
                        label: modelData.name
                        hint: modelData.isLoggedIn ? (modelData.isTokenExpired ? qsTr("Session expired: sign in again") : qsTr("Signed in"))
                                                   : modelData.authUrl ? qsTr("Signs in through your browser") : qsTr("Signs in with username and password")
                        Cover {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28; height: 28
                            radius: 6
                            source: Api.cover(modelData.icon)
                        }
                        PillButton {
                            glyph: modelData.isLoggedIn && !modelData.isTokenExpired ? Icons.logOut : Icons.logIn
                            text: modelData.isLoggedIn && !modelData.isTokenExpired ? qsTr("Sign out") : qsTr("Sign in")
                            onClicked: {
                                if (modelData.isLoggedIn && !modelData.isTokenExpired)
                                    Api.logoutTracker(modelData.id, () => page.loadTrackers())
                                else
                                    app.loginTracker(modelData)
                            }
                        }
                    }
                }
            }

            Group {
                title: qsTr("Storage")
                Field {
                    last: true
                    label: qsTr("Cover cache")
                    hint: qsTr("%1 of downscaled covers on disk").arg(page.formatBytes(page.cacheBytes))
                    PillButton {
                        glyph: Icons.trash2
                        text: qsTr("Clear")
                        onClicked: {
                            ImageCache.clear()
                            page.cacheBytes = ImageCache.diskUsage()
                            app.toast(qsTr("Cover cache cleared"))
                        }
                    }
                }
            }

            Group {
                title: qsTr("Extension server")
                Field {
                    label: qsTr("Suwayomi-Server %1").arg(ServerManager.version)
                    hint: (ServerManager.attached ? qsTr("Attached to a server that was already running on %1") : qsTr("Managed by Revenant on %1")).arg(ServerManager.baseUrl)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 10; radius: 5
                        color: ServerManager.state === ServerManager.Ready ? Theme.accent : ServerManager.state === ServerManager.Failed ? Theme.danger : Theme.warning
                    }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: ServerManager.statusText; color: Theme.textDim; font.pixelSize: 13 }
                }
                Field {
                    label: qsTr("Data directory")
                    hint: ServerManager.dataDir
                    PillButton { glyph: Icons.externalLink; text: qsTr("Open"); onClicked: Qt.openUrlExternally("file://" + ServerManager.dataDir) }
                }
                Field {
                    last: true
                    label: qsTr("Restart server")
                    hint: qsTr("Stops and relaunches the sidecar. Reading is paused until it's back.")
                    PillButton { glyph: Icons.refreshCw; text: qsTr("Restart"); enabled: !ServerManager.attached; onClicked: ServerManager.restart() }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10
                Text { text: qsTr("Server log"); font.family: Theme.display; font.pixelSize: 21; font.weight: Font.Medium; color: Theme.text }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 240
                    radius: Theme.radiusL
                    color: Theme.ink
                    border.color: Theme.stroke
                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 14
                        TextArea {
                            readOnly: true
                            text: ServerManager.log.slice(-150).join("\n")
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            color: Theme.textDim
                            wrapMode: TextArea.WrapAnywhere
                            background: null
                            selectByMouse: true
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    text: "Revenant " + Qt.application.version
                    font.family: Theme.display
                    font.italic: true
                    font.pixelSize: 20
                    color: Theme.text
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("Sources run in Suwayomi-Server (MPL-2.0). Extensions come from the Keiyoushi repository. Type set in Fraunces and Inter (SIL OFL); icons from Lucide (ISC).")
                    font.pixelSize: 13
                    lineHeight: 1.35
                    color: Theme.textFaint
                }
            }
        }
    }
}
