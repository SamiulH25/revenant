pragma Singleton
import QtQuick
import Revenant

// Named operations over the Suwayomi GraphQL API. Every function takes a
// node-style callback: cb(error, result).
QtObject {
    id: api

    readonly property string keiyoushiIndex: "https://github.com/keiyoushi/extensions/raw/repo/index.pb"

    readonly property string mangaCard: "id title thumbnailUrl thumbnailUrlLastFetched inLibrary unreadCount"
    readonly property string mangaFull: api.mangaCard + " author artist description genre status realUrl initialized inLibraryAt chaptersLastFetchedAt source { id displayName lang }"
    readonly property string chapterFields: "id name chapterNumber scanlator uploadDate isRead isBookmarked isDownloaded lastPageRead pageCount lastReadAt sourceOrder"

    // Cache key for a server image path. The fetched-at stamp busts the disk
    // cache when a source replaces a cover.
    function coverKey(path, stamp) {
        return path && stamp ? path + "?v=" + stamp : (path || "")
    }

    // image://cover URL for any server-relative image path.
    function cover(path, stamp) {
        const key = coverKey(path, stamp)
        return key ? "image://cover/" + encodeURIComponent(key) : ""
    }

    function mangaCover(manga) {
        return manga ? cover(manga.thumbnailUrl, manga.thumbnailUrlLastFetched) : ""
    }

    // Requests made before the server is up (pages load at startup, or during
    // a restart) wait here and go out once it answers.
    property var pending: []
    property Connections serverWatch: Connections {
        target: ServerManager
        function onReady() {
            const queued = api.pending
            api.pending = []
            for (const call of queued)
                api.run.apply(api, call)
        }
    }

    function run(query, variables, cb, pick) {
        if (ServerManager.state !== ServerManager.Ready) {
            pending.push([query, variables, cb, pick])
            return
        }
        Gql.request(query, variables || {}, function (error, data) {
            if (!cb)
                return
            if (error)
                cb(error, null)
            else
                cb("", pick ? pick(data) : data)
        })
    }

    // "1 chapter" / "3 chapters" without a translation catalogue.
    function count(n, one, many) {
        return (n === 1 ? one : many).arg(n)
    }

    // --- Extensions -------------------------------------------------------

    // Makes sure the Keiyoushi store is registered, then refreshes the index.
    function bootstrap(cb) {
        run("{ extensionStores { nodes { indexUrl } } }", {}, function (error, data) {
            if (error)
                return cb(error)
            const known = data.extensionStores.nodes.some(s => s.indexUrl === api.keiyoushiIndex)
            if (known)
                return refreshExtensions(cb)
            run("mutation($u: String!) { addExtensionStore(input: { indexUrl: $u }) { extensionStore { name } } }",
                { u: api.keiyoushiIndex }, function (err) {
                    if (err)
                        return cb(err)
                    refreshExtensions(cb)
                })
        })
    }

    readonly property string extensionFields: "pkgName name lang versionName isInstalled hasUpdate isObsolete contentWarning iconUrl extensionStore { badgeLabel }"

    function refreshExtensions(cb) {
        run("mutation { fetchExtensions(input: {}) { extensions { " + extensionFields + " } } }", {}, cb,
            d => d.fetchExtensions.extensions)
    }

    function extensions(cb) {
        run("{ extensions(order: [{ by: NAME }]) { nodes { " + extensionFields + " } } }", {}, cb,
            d => d.extensions.nodes)
    }

    // action: "install" | "uninstall" | "update"
    function setExtension(pkgName, action, cb) {
        const patch = {}
        patch[action] = true
        run("mutation($id: String!, $p: UpdateExtensionPatchInput!) { updateExtension(input: { id: $id, patch: $p }) { extension { " + extensionFields + " } } }",
            { id: pkgName, p: patch }, cb, d => d.updateExtension.extension)
    }

    // --- Sources ----------------------------------------------------------

    function sources(cb) {
        run("{ sources(order: [{ by: NAME }]) { nodes { id name displayName lang iconUrl supportsLatest isConfigurable contentWarning extension { pkgName } } } }",
            {}, cb, d => d.sources.nodes.filter(s => s.id !== "0"))
    }

    // type: "POPULAR" | "LATEST" | "SEARCH". filters: [FilterChangeInput]
    // (see FilterSheet), only honoured for SEARCH.
    function browse(sourceId, type, page, query, cb, filters) {
        run("mutation($s: LongString!, $t: FetchSourceMangaType!, $p: Int!, $q: String, $f: [FilterChangeInput!]) { fetchSourceManga(input: { source: $s, type: $t, page: $p, query: $q, filters: $f }) { hasNextPage mangas { " + mangaCard + " } } }",
            { s: sourceId, t: type, p: page, q: query || null, f: filters && filters.length ? filters : null }, cb, d => d.fetchSourceManga)
    }

    // Filter and Preference are unions; __typename says which fields apply.
    // Same-named fields differ in type across members, hence the aliases.
    readonly property string filterFields: "__typename ... on HeaderFilter { name } ... on SeparatorFilter { name } ... on CheckBoxFilter { name checkDefault: default } ... on TriStateFilter { name triDefault: default } ... on TextFilter { name textDefault: default } ... on SelectFilter { name selectDefault: default values } ... on SortFilter { name values sortDefault: default { index ascending } }"
    readonly property string preferenceFields: "__typename ... on CheckBoxPreference { key title summary visible enabled boolValue: currentValue boolDefault: default } ... on SwitchPreference { key title summary visible enabled boolValue: currentValue boolDefault: default } ... on ListPreference { key title summary visible enabled textValue: currentValue textDefault: default entries entryValues } ... on MultiSelectListPreference { key title summary visible enabled listValue: currentValue listDefault: default entries entryValues } ... on EditTextPreference { key title summary visible enabled textValue: currentValue textDefault: default dialogTitle dialogMessage }"

    function sourceFilters(sourceId, cb) {
        run("query($id: LongString!) { source(id: $id) { filters { " + filterFields + " ... on GroupFilter { name filters { " + filterFields + " } } } } }",
            { id: sourceId }, cb, d => d.source.filters)
    }

    function sourcePreferences(sourceId, cb) {
        run("query($id: LongString!) { source(id: $id) { preferences { " + preferenceFields + " } } }",
            { id: sourceId }, cb, d => d.source.preferences)
    }

    // change: { position, switchState | checkBoxState | listState | multiSelectState | editTextState }
    function setSourcePreference(sourceId, change, cb) {
        run("mutation($s: LongString!, $c: SourcePreferenceChangeInput!) { updateSourcePreference(input: { source: $s, change: $c }) { preferences { " + preferenceFields + " } } }",
            { s: sourceId, c: change }, cb, d => d.updateSourcePreference.preferences)
    }

    // --- Manga ------------------------------------------------------------

    // The nested manga.chapters field takes no arguments, so ordered
    // chapters come from the top-level query and are attached here.
    function manga(id, cb) {
        run("query($id: Int!) { manga(id: $id) { " + mangaFull + " } chapters(condition: { mangaId: $id }, order: [{ by: SOURCE_ORDER, byType: DESC }]) { nodes { " + chapterFields + " } } }",
            { id: id }, cb, d => {
                d.manga.chapters = d.chapters
                return d.manga
            })
    }

    // Pulls fresh details and chapter list from the source.
    function refreshManga(id, cb) {
        run("mutation($id: Int!) { fetchMangaAndChapters(input: { id: $id, fetchManga: true, fetchChapters: true }) { manga { " + mangaFull + " } chapters { " + chapterFields + " } } }",
            { id: id }, cb, d => {
                const m = d.fetchMangaAndChapters.manga
                m.chapters = { nodes: d.fetchMangaAndChapters.chapters.slice().sort((a, b) => b.sourceOrder - a.sourceOrder) }
                return m
            })
    }

    function setInLibrary(id, inLibrary, cb) {
        run("mutation($id: Int!, $v: Boolean!) { updateManga(input: { id: $id, patch: { inLibrary: $v } }) { manga { id inLibrary } } }",
            { id: id, v: inLibrary }, cb, d => d.updateManga.manga)
    }

    function library(cb) {
        run("{ mangas(condition: { inLibrary: true }) { nodes { " + mangaCard + " inLibraryAt lastReadChapter { lastReadAt } latestUploadedChapter { uploadDate } source { displayName } categories { nodes { id } } } } }",
            {}, cb, d => d.mangas.nodes)
    }

    function updateLibrary(cb) {
        run("mutation { updateLibrary(input: {}) { updateStatus { jobsInfo { isRunning totalJobs finishedJobs } } } }",
            {}, cb, d => d.updateLibrary.updateStatus.jobsInfo)
    }

    function libraryUpdateStatus(cb) {
        run("{ libraryUpdateStatus { jobsInfo { isRunning totalJobs finishedJobs } } }", {}, cb,
            d => d.libraryUpdateStatus.jobsInfo)
    }

    // --- Categories -------------------------------------------------------
    // Category 0 is Suwayomi's built-in "Default": titles with no category.

    function categories(cb) {
        run("{ categories(order: [{ by: ORDER }]) { nodes { id name order default } } }", {}, cb,
            d => d.categories.nodes)
    }

    function createCategory(name, cb) {
        run("mutation($n: String!) { createCategory(input: { name: $n }) { category { id name order } } }",
            { n: name }, cb, d => d.createCategory.category)
    }

    function renameCategory(id, name, cb) {
        run("mutation($id: Int!, $n: String!) { updateCategory(input: { id: $id, patch: { name: $n } }) { category { id name } } }",
            { id: id, n: name }, cb, d => d.updateCategory.category)
    }

    function deleteCategory(id, cb) {
        run("mutation($id: Int!) { deleteCategory(input: { categoryId: $id }) { category { id } } }",
            { id: id }, cb, d => d.deleteCategory)
    }

    function moveCategory(id, position, cb) {
        run("mutation($id: Int!, $p: Int!) { updateCategoryOrder(input: { id: $id, position: $p }) { categories { id name order default } } }",
            { id: id, p: position }, cb, d => d.updateCategoryOrder.categories)
    }

    function mangaCategories(mangaId, cb) {
        run("query($id: Int!) { manga(id: $id) { categories { nodes { id } } } }", { id: mangaId }, cb,
            d => d.manga.categories.nodes.map(c => c.id))
    }

    function setMangaCategories(mangaId, add, remove, cb) {
        run("mutation($id: Int!, $a: [Int!], $r: [Int!]) { updateMangaCategories(input: { id: $id, patch: { addToCategories: $a, removeFromCategories: $r } }) { manga { id categories { nodes { id } } } } }",
            { id: mangaId, a: add, r: remove }, cb, d => d.updateMangaCategories.manga)
    }

    // --- Tracking ---------------------------------------------------------

    readonly property string trackerFields: "id name icon isLoggedIn isTokenExpired authUrl scores statuses { name value } supportsPrivateTracking"
    readonly property string recordFields: "id trackerId remoteId remoteUrl title status score displayScore lastChapterRead totalChapters private"

    function trackers(cb) {
        run("{ trackers { nodes { " + trackerFields + " } } }", {}, cb, d => d.trackers.nodes)
    }

    function loginTrackerOAuth(trackerId, callbackUrl, cb) {
        run("mutation($t: Int!, $u: String!) { loginTrackerOAuth(input: { trackerId: $t, callbackUrl: $u }) { isLoggedIn } }",
            { t: trackerId, u: callbackUrl }, cb, d => d.loginTrackerOAuth.isLoggedIn)
    }

    function loginTrackerCredentials(trackerId, username, password, cb) {
        run("mutation($t: Int!, $u: String!, $p: String!) { loginTrackerCredentials(input: { trackerId: $t, username: $u, password: $p }) { isLoggedIn } }",
            { t: trackerId, u: username, p: password }, cb, d => d.loginTrackerCredentials.isLoggedIn)
    }

    function logoutTracker(trackerId, cb) {
        run("mutation($t: Int!) { logoutTracker(input: { trackerId: $t }) { isLoggedIn } }", { t: trackerId }, cb,
            d => d.logoutTracker.isLoggedIn)
    }

    function trackRecords(mangaId, cb) {
        run("query($id: Int!) { manga(id: $id) { trackRecords { nodes { " + recordFields + " } } } }", { id: mangaId }, cb,
            d => d.manga.trackRecords.nodes)
    }

    function searchTracker(trackerId, query, cb) {
        run("query($t: Int!, $q: String!) { searchTracker(input: { trackerId: $t, query: $q }) { trackSearches { remoteId title coverUrl summary publishingStatus publishingType startDate totalChapters trackingUrl } } }",
            { t: trackerId, q: query }, cb, d => d.searchTracker.trackSearches)
    }

    function bindTrack(mangaId, trackerId, remoteId, cb) {
        run("mutation($m: Int!, $t: Int!, $r: LongString!) { bindTrack(input: { mangaId: $m, trackerId: $t, remoteId: $r }) { trackRecord { " + recordFields + " } } }",
            { m: mangaId, t: trackerId, r: remoteId }, cb, d => d.bindTrack.trackRecord)
    }

    // patch: { status?, lastChapterRead?, scoreString?, private? }
    function updateTrack(recordId, patch, cb) {
        run("mutation($i: UpdateTrackInput!) { updateTrack(input: $i) { trackRecord { " + recordFields + " } } }",
            { i: Object.assign({ recordId: recordId }, patch) }, cb, d => d.updateTrack.trackRecord)
    }

    function unbindTrack(recordId, deleteRemote, cb) {
        run("mutation($r: Int!, $d: Boolean) { unbindTrack(input: { recordId: $r, deleteRemoteTrack: $d }) { trackRecord { id } } }",
            { r: recordId, d: !!deleteRemote }, cb, d => d.unbindTrack)
    }

    // Pushes read progress to every tracker bound to the title.
    function trackProgress(mangaId, cb) {
        run("mutation($m: Int!) { trackProgress(input: { mangaId: $m }) { trackRecords { id } } }", { m: mangaId }, cb,
            d => d.trackProgress)
    }

    // --- Downloads --------------------------------------------------------

    readonly property string downloadFields: "state queue { position progress state tries chapter { id name mangaId } manga { " + mangaCard + " } }"

    function downloadStatus(cb) {
        run("{ downloadStatus { " + downloadFields + " } }", {}, cb, d => d.downloadStatus)
    }

    function enqueueDownloads(ids, cb) {
        run("mutation($ids: [Int!]!) { enqueueChapterDownloads(input: { ids: $ids }) { downloadStatus { " + downloadFields + " } } }",
            { ids: ids }, cb, d => d.enqueueChapterDownloads.downloadStatus)
    }

    function dequeueDownloads(ids, cb) {
        run("mutation($ids: [Int!]!) { dequeueChapterDownloads(input: { ids: $ids }) { downloadStatus { " + downloadFields + " } } }",
            { ids: ids }, cb, d => d.dequeueChapterDownloads.downloadStatus)
    }

    function deleteDownloads(ids, cb) {
        run("mutation($ids: [Int!]!) { deleteDownloadedChapters(input: { ids: $ids }) { chapters { id isDownloaded } } }",
            { ids: ids }, cb, d => d.deleteDownloadedChapters.chapters)
    }

    function reorderDownload(chapterId, to, cb) {
        run("mutation($c: Int!, $t: Int!) { reorderChapterDownload(input: { chapterId: $c, to: $t }) { downloadStatus { " + downloadFields + " } } }",
            { c: chapterId, t: to }, cb, d => d.reorderChapterDownload.downloadStatus)
    }

    // action: "start" | "stop" | "clear"
    function downloader(action, cb) {
        const name = action === "start" ? "startDownloader" : action === "stop" ? "stopDownloader" : "clearDownloader"
        run("mutation { " + name + "(input: {}) { downloadStatus { " + downloadFields + " } } }", {}, cb,
            d => d[name].downloadStatus)
    }

    // Every downloaded chapter, for the "On disk" view.
    function downloadedChapters(cb) {
        run("{ chapters(condition: { isDownloaded: true }, order: [{ by: SOURCE_ORDER }]) { nodes { id name mangaId pageCount manga { " + mangaCard + " } } } }",
            {}, cb, d => d.chapters.nodes)
    }

    // --- Server settings --------------------------------------------------

    readonly property string settingsFields: "downloadAsCbz downloadsPath autoDownloadNewChapters autoDownloadNewChaptersLimit excludeEntryWithUnreadChapters globalUpdateInterval updateMangas"

    function serverSettings(cb) {
        run("{ settings { " + settingsFields + " } }", {}, cb, d => d.settings)
    }

    function setServerSettings(patch, cb) {
        run("mutation($s: PartialSettingsTypeInput!) { setSettings(input: { settings: $s }) { settings { " + settingsFields + " } } }",
            { s: patch }, cb, d => d.setSettings.settings)
    }

    // --- Chapters ---------------------------------------------------------

    function pages(chapterId, cb) {
        run("mutation($id: Int!) { fetchChapterPages(input: { chapterId: $id }) { pages chapter { " + chapterFields + " } } }",
            { id: chapterId }, cb, d => d.fetchChapterPages)
    }

    // patch: { isRead?, isBookmarked?, lastPageRead? }
    function updateChapters(ids, patch, cb) {
        run("mutation($ids: [Int!]!, $p: UpdateChapterPatchInput!) { updateChapters(input: { ids: $ids, patch: $p }) { chapters { id isRead isBookmarked lastPageRead lastReadAt } } }",
            { ids: ids, p: patch }, cb, d => d.updateChapters.chapters)
    }

    // Picks where to continue: the most recently opened chapter if it isn't
    // finished, else the one after it; with no history, the earliest unread.
    // chapters must be ordered newest first, as manga() returns them.
    function resumeChapter(chapters) {
        let last = -1
        for (let i = 0; i < chapters.length; ++i) {
            if (Number(chapters[i].lastReadAt) > 0 && (last < 0 || Number(chapters[i].lastReadAt) > Number(chapters[last].lastReadAt)))
                last = i
        }
        if (last >= 0)
            return chapters[last].isRead && last > 0 ? chapters[last - 1] : chapters[last]
        for (let j = chapters.length - 1; j >= 0; --j) {
            if (!chapters[j].isRead)
                return chapters[j]
        }
        return chapters.length ? chapters[chapters.length - 1] : null
    }

    // Suwayomi stamps reads in epoch seconds (uploads are in milliseconds).
    function readDate(seconds) {
        return new Date(Number(seconds) * 1000)
    }

    function history(cb) {
        run("{ chapters(filter: { lastReadAt: { greaterThan: \"0\" } }, order: [{ by: LAST_READ_AT, byType: DESC }], first: 150) { nodes { " + chapterFields + " mangaId manga { " + mangaCard + " } } } }",
            {}, cb, d => d.chapters.nodes)
    }
}
