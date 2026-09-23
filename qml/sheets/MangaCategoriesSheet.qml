import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

// Choose which categories one title belongs to.
Sheet {
    id: sheet

    property var manga
    property var categories: []
    property var selected: []   // category ids
    property var initial: []
    signal saved()

    title: qsTr("Move to categories")
    subtitle: manga ? manga.title : ""

    function openFor(m) {
        manga = m
        busy = true
        open()
        Api.categories(function (error, list) {
            if (error) {
                busy = false
                return app.toast(error, "error")
            }
            categories = list.filter(c => c.id !== 0)
            Api.mangaCategories(m.id, function (err, ids) {
                busy = false
                initial = err ? [] : ids
                selected = initial.slice()
            })
        })
    }

    function toggle(id) {
        selected = selected.indexOf(id) >= 0 ? selected.filter(x => x !== id) : selected.concat([id])
    }

    Text {
        visible: sheet.categories.length === 0 && !sheet.busy
        Layout.fillWidth: true
        text: qsTr("You haven't made any categories. Create them from the Library page.")
        wrapMode: Text.WordWrap
        font.pixelSize: 13
        color: Theme.textDim
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: sheet.categories
            Chip {
                required property var modelData
                checkable: false
                checked: sheet.selected.indexOf(modelData.id) >= 0
                text: modelData.name
                implicitHeight: 34
                onClicked: sheet.toggle(modelData.id)
            }
        }
    }

    footerItems: [
        Item { Layout.fillWidth: true },
        PillButton { text: qsTr("Cancel"); onClicked: sheet.close() },
        PillButton {
            primary: true
            glyph: Icons.check
            text: qsTr("Save")
            enabled: sheet.categories.length > 0
            onClicked: {
                const add = sheet.selected.filter(id => sheet.initial.indexOf(id) < 0)
                const remove = sheet.initial.filter(id => sheet.selected.indexOf(id) < 0)
                Api.setMangaCategories(sheet.manga.id, add, remove, function (error) {
                    if (error)
                        return app.toast(error, "error")
                    sheet.close()
                    sheet.saved()
                    app.libraryRevision++
                })
            }
        }
    ]
}
