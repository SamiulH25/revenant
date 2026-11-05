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
    property bool readerDoublePage: false     // two-page spreads in paged modes
    property bool readerSpreadOffset: true    // cover page alone before the first spread
    property int webtoonWidth: 820            // max strip width in px
    property int webtoonGap: 0
    property string readerBackground: "ambient" // ambient | black | gray | white
    property string readerTurn: "curl"        // curl | slide | fade | none (paged modes)
    property int autoplaySeconds: 8           // paged autoplay: seconds per page
    property int autoscrollSpeed: 90          // webtoon autoscroll: pixels per second
    property bool readerDoubleTap: true
    property bool autoMarkRead: true
    property int preloadPages: 4

    // Library & browsing
    property int coverSize: 180
    property int libraryCategory: -1          // -1 = all
    property string librarySort: "recent"     // recent | title | unread | added
    property bool libraryUnreadOnly: false
    property bool showNsfw: false
    property var languages: ["en", "all"]
    property string lastSourceId: ""
    property var pinnedSources: []            // source ids shown first in Discover
    property var recentSearches: []           // newest first
    property var recentSources: []            // source ids, most recently opened first
}
