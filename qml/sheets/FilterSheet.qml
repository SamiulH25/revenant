import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

// Right-hand drawer with a source's own search filters. Emits applied() with
// the FilterChangeInput list for everything that differs from the defaults.
Drawer {
    id: sheet

    property string sourceId
    property var filters: []
    property var values: []
    property bool loading: false
    property string error
    property var openGroups: ({})

    readonly property var changes: changesFor(values)
    signal applied(var changes)

    edge: Qt.RightEdge
    width: Math.min(440, parent ? parent.width - 80 : 440)
    height: parent ? parent.height : 600
    parent: Overlay.overlay
    padding: 0

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.5) }
    background: Rectangle {
        color: Theme.raised
        Rectangle { width: 1; height: parent.height; color: Theme.strokeStrong }
    }

    function defaultOf(f) {
        switch (f.__typename) {
        case "CheckBoxFilter": return f.checkDefault
        case "TriStateFilter": return f.triDefault
        case "TextFilter": return f.textDefault || ""
        case "SelectFilter": return f.selectDefault
        case "SortFilter": return f.sortDefault ? { index: f.sortDefault.index, ascending: f.sortDefault.ascending } : null
        case "GroupFilter": return f.filters.map(defaultOf)
        default: return null
        }
    }

    function changeFor(f, value, position) {
        const d = defaultOf(f)
        switch (f.__typename) {
        case "CheckBoxFilter": return value !== d ? { position: position, checkBoxState: value } : null
        case "TriStateFilter": return value !== d ? { position: position, triState: value } : null
        case "TextFilter": return value !== d ? { position: position, textState: value } : null
        case "SelectFilter": return value !== d ? { position: position, selectState: value } : null
        case "SortFilter":
            if (!value || (d && d.index === value.index && d.ascending === value.ascending))
                return null
            return { position: position, sortState: value }
        default: return null
        }
    }

    function changesFor(vals) {
        const out = []
        if (vals.length !== filters.length)
            return out
        filters.forEach((f, i) => {
            if (f.__typename === "GroupFilter") {
                f.filters.forEach((child, j) => {
                    const c = changeFor(child, vals[i][j], j)
                    if (c)
                        out.push({ position: i, groupChange: c })
                })
            } else {
                const c = changeFor(f, vals[i], i)
                if (c)
                    out.push(c)
            }
        })
        return out
    }

    function load(id) {
        if (id === sourceId && filters.length)
            return
        sourceId = id
        loading = true
        error = ""
        Api.sourceFilters(id, function (err, list) {
            loading = false
            if (err) {
                error = err
                return
            }
            values = list.map(defaultOf)
            filters = list
        })
    }

    function setValue(i, j, v) {
        const next = values.slice()
        if (j >= 0) {
            next[i] = next[i].slice()
            next[i][j] = v
        } else {
            next[i] = v
        }
        values = next
    }

    function reset() {
        values = filters.map(defaultOf)
    }

    function groupActive(i) {
        return changes.filter(c => c.position === i && c.groupChange).length
    }

    function toggleGroup(i) {
        const g = Object.assign({}, openGroups)
        g[i] = !g[i]
        openGroups = g
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 24
            Layout.bottomMargin: 14
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: qsTr("Filters")
                    font.family: Theme.display
                    font.pixelSize: 26
                    font.weight: Font.Medium
                    color: Theme.text
                }
                Text {
                    text: sheet.changes.length ? qsTr("%n active", "", sheet.changes.length) : qsTr("Source defaults")
                    font.pixelSize: 12
                    color: sheet.changes.length ? Theme.accent : Theme.textFaint
                }
            }
            IconButton { glyph: Icons.x; tip: qsTr("Close"); onClicked: sheet.close() }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.stroke }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: list.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}

            Column {
                id: list
                x: 24
                y: 20
                width: flick.width - 48
                spacing: 16

                Spinner { visible: sheet.loading; size: 22; anchors.horizontalCenter: parent.horizontalCenter }
                Text {
                    visible: sheet.error.length > 0
                    width: parent.width
                    text: sheet.error
                    wrapMode: Text.WordWrap
                    color: Theme.danger
                }
                Text {
                    visible: !sheet.loading && !sheet.error && sheet.filters.length === 0
                    text: qsTr("This source has no filters.")
                    color: Theme.textDim
                }

                Repeater {
                    model: sheet.filters
                    delegate: Column {
                        id: top
                        required property var modelData
                        required property int index
                        readonly property bool isGroup: modelData.__typename === "GroupFilter"
                        readonly property bool open: !!sheet.openGroups[index]
                        width: list.width
                        spacing: 10

                        FilterItem {
                            visible: !top.isGroup
                            filter: top.isGroup ? null : top.modelData
                            value: sheet.values[top.index]
                            fullWidth: list.width
                            onEdited: v => sheet.setValue(top.index, -1, v)
                        }

                        // Group: a collapsible section.
                        AbstractButton {
                            visible: top.isGroup
                            width: list.width
                            height: 40
                            hoverEnabled: true
                            focusPolicy: Qt.NoFocus
                            onClicked: sheet.toggleGroup(top.index)
                            background: Rectangle {
                                radius: Theme.radiusM
                                color: parent.hovered ? Theme.hover : Theme.surface
                                border.color: Theme.stroke
                            }
                            contentItem: RowLayout {
                                spacing: 8
                                Text {
                                    Layout.leftMargin: 14
                                    Layout.fillWidth: true
                                    text: top.modelData.name
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    color: Theme.text
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    readonly property int n: top.isGroup ? sheet.groupActive(top.index) : 0
                                    visible: n > 0
                                    implicitWidth: Math.max(20, countText.implicitWidth + 10)
                                    implicitHeight: 20
                                    radius: 10
                                    color: Theme.accent
                                    Text { id: countText; anchors.centerIn: parent; text: parent.n; font.pixelSize: 11; font.weight: Font.Bold; color: Theme.accentInk }
                                }
                                Icon {
                                    Layout.rightMargin: 12
                                    glyph: top.open ? Icons.chevronUp : Icons.chevronDown
                                    size: 14
                                    color: Theme.textDim
                                }
                            }
                        }

                        Flow {
                            visible: top.isGroup && top.open
                            width: list.width
                            spacing: 6
                            Repeater {
                                model: top.isGroup && top.open ? top.modelData.filters : []
                                FilterItem {
                                    required property var modelData
                                    required property int index
                                    filter: modelData
                                    value: sheet.values[top.index] ? sheet.values[top.index][index] : null
                                    fullWidth: list.width
                                    onEdited: v => sheet.setValue(top.index, index, v)
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.stroke }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 20
            spacing: 10
            PillButton {
                glyph: Icons.undo2
                text: qsTr("Reset")
                enabled: sheet.changes.length > 0
                onClicked: sheet.reset()
            }
            Item { Layout.fillWidth: true }
            PillButton {
                primary: true
                glyph: Icons.filter
                text: qsTr("Apply")
                onClicked: {
                    sheet.applied(sheet.changes)
                    sheet.close()
                }
            }
        }
    }
}
