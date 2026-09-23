import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

// An extension's own preferences (quality, language, mirrors, ...).
Sheet {
    id: sheet

    property var source
    property var prefs: []
    property bool loading: false

    title: source ? qsTr("%1 settings").arg(source.name) : ""
    subtitle: source ? source.displayName : ""
    busy: loading
    preferredWidth: 600

    function load(src) {
        source = src
        prefs = []
        loading = true
        open()
        Api.sourcePreferences(src.id, function (err, list) {
            loading = false
            if (err)
                return app.toast(err, "error")
            prefs = list
        })
    }

    function change(position, patch) {
        loading = true
        Api.setSourcePreference(source.id, Object.assign({ position: position }, patch), function (err, list) {
            loading = false
            if (err)
                return app.toast(err, "error")
            prefs = list
        })
    }

    Text {
        visible: !sheet.loading && sheet.prefs.length === 0
        text: qsTr("This extension has no settings.")
        color: Theme.textDim
        font.pixelSize: 13
    }

    Repeater {
        model: sheet.prefs
        delegate: ColumnLayout {
            id: pref
            required property var modelData
            required property int index
            readonly property string kind: modelData.__typename
            readonly property bool isBool: kind === "SwitchPreference" || kind === "CheckBoxPreference"
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            visible: modelData.visible !== false
            enabled: modelData.enabled !== false
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: pref.modelData.title || pref.modelData.key || ""
                        wrapMode: Text.WordWrap
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        color: Theme.text
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        // Android summaries use %s for the current entry.
                        text: {
                            const m = pref.modelData
                            let text = m.summary || ""
                            if (text.indexOf("%s") >= 0 && m.entries) {
                                const i = m.entryValues.indexOf(m.textValue ?? m.textDefault)
                                text = text.replace("%s", i >= 0 ? m.entries[i] : "")
                            }
                            return text
                        }
                        wrapMode: Text.WordWrap
                        font.pixelSize: 12
                        color: Theme.textFaint
                    }
                }
                Toggle {
                    visible: pref.isBool
                    checked: pref.isBool && (pref.modelData.boolValue !== null && pref.modelData.boolValue !== undefined
                                             ? pref.modelData.boolValue : pref.modelData.boolDefault)
                    onToggled: sheet.change(pref.index, pref.kind === "SwitchPreference" ? { switchState: checked } : { checkBoxState: checked })
                }
                Dropdown {
                    visible: pref.kind === "ListPreference"
                    Layout.preferredWidth: 220
                    model: pref.kind === "ListPreference" ? pref.modelData.entries : []
                    currentIndex: pref.kind === "ListPreference"
                                  ? pref.modelData.entryValues.indexOf(pref.modelData.textValue ?? pref.modelData.textDefault) : -1
                    onActivated: i => sheet.change(pref.index, { listState: pref.modelData.entryValues[i] })
                }
            }

            Flow {
                Layout.fillWidth: true
                visible: pref.kind === "MultiSelectListPreference"
                spacing: 6
                Repeater {
                    model: pref.kind === "MultiSelectListPreference" ? pref.modelData.entries : []
                    Chip {
                        required property string modelData
                        required property int index
                        readonly property string entryValue: pref.modelData.entryValues[index]
                        readonly property var current: pref.modelData.listValue ?? pref.modelData.listDefault ?? []
                        checkable: false
                        checked: current.indexOf(entryValue) >= 0
                        text: modelData
                        onClicked: {
                            const next = checked ? current.filter(v => v !== entryValue) : current.concat([entryValue])
                            sheet.change(pref.index, { multiSelectState: next })
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: pref.kind === "EditTextPreference"
                spacing: 8
                TextBox {
                    id: editBox
                    Layout.fillWidth: true
                    text: pref.kind === "EditTextPreference" ? (pref.modelData.textValue ?? pref.modelData.textDefault ?? "") : ""
                    placeholderText: pref.modelData.dialogMessage || ""
                    onAccepted: sheet.change(pref.index, { editTextState: text })
                }
                PillButton {
                    implicitHeight: 38
                    text: qsTr("Save")
                    onClicked: sheet.change(pref.index, { editTextState: editBox.text })
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                Layout.preferredHeight: 1
                color: Theme.stroke
                visible: pref.index < sheet.prefs.length - 1
            }
        }
    }
}
