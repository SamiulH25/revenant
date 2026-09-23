import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

// Create, rename, reorder and delete library categories.
Sheet {
    id: sheet

    property var categories: []
    signal changed()

    title: qsTr("Categories")
    subtitle: qsTr("Group your library into shelves")

    readonly property var own: categories.filter(c => c.id !== 0)

    function load() {
        busy = true
        Api.categories(function (error, list) {
            busy = false
            if (error)
                return app.toast(error, "error")
            categories = list
        })
    }

    function done(error) {
        if (error)
            return app.toast(error, "error")
        load()
        changed()
    }

    onOpened: load()

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        TextBox {
            id: newName
            Layout.fillWidth: true
            placeholderText: qsTr("New category")
            onAccepted: addButton.clicked()
        }
        PillButton {
            id: addButton
            implicitHeight: 38
            primary: true
            glyph: Icons.plus
            text: qsTr("Add")
            enabled: newName.text.trim().length > 0
            onClicked: {
                Api.createCategory(newName.text.trim(), error => sheet.done(error))
                newName.clear()
            }
        }
    }

    Text {
        visible: sheet.own.length === 0 && !sheet.busy
        Layout.topMargin: 8
        text: qsTr("No categories yet. Titles without one sit on the default shelf.")
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        font.pixelSize: 13
        color: Theme.textDim
    }

    Repeater {
        model: sheet.own
        delegate: RowLayout {
            id: row
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 6

            TextBox {
                Layout.fillWidth: true
                text: row.modelData.name
                onEditingFinished: if (text.trim() && text.trim() !== row.modelData.name)
                    Api.renameCategory(row.modelData.id, text.trim(), error => sheet.done(error))
            }
            IconButton {
                glyph: Icons.chevronUp
                tip: qsTr("Move up")
                enabled: row.index > 0
                onClicked: Api.moveCategory(row.modelData.id, row.modelData.order - 1, error => sheet.done(error))
            }
            IconButton {
                glyph: Icons.chevronDown
                tip: qsTr("Move down")
                enabled: row.index < sheet.own.length - 1
                onClicked: Api.moveCategory(row.modelData.id, row.modelData.order + 1, error => sheet.done(error))
            }
            IconButton {
                glyph: Icons.trash2
                tip: qsTr("Delete (titles stay in your library)")
                tint: Theme.danger
                onClicked: Api.deleteCategory(row.modelData.id, error => sheet.done(error))
            }
        }
    }
}
