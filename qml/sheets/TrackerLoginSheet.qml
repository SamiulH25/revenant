import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Revenant

// Username/password sign-in for trackers without OAuth (Kitsu, MangaUpdates).
Sheet {
    id: sheet

    property var tracker
    signal signedIn()

    title: tracker ? qsTr("Sign in to %1").arg(tracker.name) : ""
    subtitle: qsTr("Your password goes to the tracker through the local server only.")
    preferredWidth: 440

    function openFor(t) {
        tracker = t
        user.clear()
        pass.clear()
        open()
        user.forceActiveFocus()
    }

    function submit() {
        busy = true
        Api.loginTrackerCredentials(tracker.id, user.text.trim(), pass.text, function (error, ok) {
            busy = false
            if (error || !ok)
                return app.toast(error || qsTr("Sign-in failed"), "error")
            sheet.close()
            app.toast(qsTr("Signed in to %1").arg(tracker.name))
            sheet.signedIn()
        })
    }

    TextBox { id: user; Layout.fillWidth: true; placeholderText: qsTr("Username or email"); onAccepted: pass.forceActiveFocus() }
    TextBox { id: pass; Layout.fillWidth: true; placeholderText: qsTr("Password"); echoMode: TextInput.Password; onAccepted: sheet.submit() }

    footerItems: [
        Item { Layout.fillWidth: true },
        PillButton { text: qsTr("Cancel"); onClicked: sheet.close() },
        PillButton {
            primary: true
            glyph: Icons.logIn
            text: qsTr("Sign in")
            enabled: user.text.trim().length > 0 && pass.text.length > 0 && !sheet.busy
            onClicked: sheet.submit()
        }
    ]
}
