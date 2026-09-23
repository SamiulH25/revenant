pragma Singleton
import QtQuick
import QtCore

// User preferences, persisted to ~/.config/revenant/revenant.conf.
Settings {
    location: StandardPaths.writableLocation(StandardPaths.AppConfigLocation) + "/revenant.conf"
    category: "prefs"

    // Reader
    property string readerMode: "paged-rtl"   // paged-rtl | paged-ltr | webtoon
    property string readerFit: "height"       // height | width | original (paged modes)
    property int webtoonWidth: 820            // max strip width in px
    property int webtoonGap: 0
    property string readerBackground: "black" // black | gray | white
    property bool readerDoubleTap: true
    property bool autoMarkRead: true
    property int preloadPages: 4

    // Library & browsing
    property int coverSize: 180
    property string librarySort: "recent"     // recent | title | unread | added
    property bool libraryUnreadOnly: false
    property bool showNsfw: false
    property var languages: ["en", "all"]
    property string lastSourceId: ""
}
