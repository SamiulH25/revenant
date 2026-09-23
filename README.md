# Revenant

A native desktop manga reader for Linux, built with Qt 6 / QML. It reads from
the [Keiyoushi](https://keiyoushi.github.io) extension catalog (the same
extensions Mihon uses).

Keiyoushi extensions are compiled Android/JVM code, so Revenant runs them in
[Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server), a headless JVM
sidecar it manages itself. On first launch it downloads the latest server jar
from GitHub, checks its SHA-256, starts it on `127.0.0.1:4577`, adds the
Keiyoushi store, and stops the server again when you quit. If a Suwayomi server
is already listening on that port, Revenant uses it instead of starting one.

## Features

- **Library** with a Continue reading shelf, categories, unread badges,
  sorting and filtering, and library updates (manual or scheduled).
- **Browse** sources by language, search one source or all of them at once,
  and narrow results with each source's own filters (tags, sort, status...).
  Configurable sources have a settings sheet (quality, languages, ...).
- **Extensions** from the Keiyoushi catalog: install, update, remove.
- **Reader** with Manga (right-to-left), Comic and Webtoon modes, two-page
  spreads, zoom, preloading, saved progress and chapter-to-chapter flow.
- **Downloads** for offline reading, with a live queue and per-title storage.
- **Tracking** with AniList, MyAnimeList, Kitsu, MangaUpdates, Shikimori and
  Bangumi: link titles, and progress syncs as you finish chapters.

## Requirements

- Qt 6.5+ (Base, Declarative, ShaderTools, ImageFormats for WebP covers)
- CMake 3.21+, Ninja, a C++20 compiler
- Java 21+ for the server (`java` on `PATH`, `JAVA_HOME`, or `REVENANT_JAVA`)

## Build and run

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build
./build/revenant
```

`cmake --install build` installs the binary, a desktop entry and the icon.

## Where things live

| What | Path |
| --- | --- |
| Server jar | `~/.local/share/revenant/server/` |
| Library, extensions, page cache | `~/.local/share/revenant/data/` |
| Downscaled cover cache | `~/.cache/revenant/covers/` |
| Preferences | `~/.config/revenant/revenant.conf` |

## Reader keys

| Key | Action |
| --- | --- |
| ← → / A D | Turn page (follows reading direction on screen) |
| Space, ↓, PgDn / Shift+Space, ↑, PgUp | Forward / back (scrolls tall pages first) |
| Home / End | First / last page |
| ] or N / [ or P | Next / previous chapter |
| M | Cycle Manga (RTL) → Comic (LTR) → Webtoon |
| 2 / O | Toggle two-page spreads / shift the pairing by one page |
| Z, Ctrl+wheel, double-click centre | Zoom |
| F / F11 | Fullscreen |
| H / Tab | Toggle the reader controls |
| Esc / Q / Backspace | Close the reader |

Clicking the left or right third of a page turns it; the middle toggles the
controls. App-wide: Ctrl+1–5 switch sections, Ctrl+, opens settings,
Ctrl+F focuses search, Ctrl+R updates the library, Alt+← / mouse back goes back.

## Layout

```
src/
  servermanager.*    Suwayomi sidecar: Java lookup, jar download + checksum, launch, shutdown
  graphqlclient.*    GraphQL transport exposed to QML as the Gql singleton
  imagecache.*       image://cover provider: downscaled on-disk covers + cover accent colours
  keyedlistmodel.*   list model that diffs updates by key (keeps scroll position)
  oauthreceiver.*    loopback listener that completes tracker OAuth sign-in
  devscript.*        REVENANT_SCRIPT automation for screenshots and smoke tests
qml/
  Api.qml            named GraphQL operations
  Theme.qml Prefs.qml Icons.qml
  components/        design-system pieces (Cover, MangaCard, Segmented, Glow, ...)
  pages/             Library, Browse, Source, Manga, History, Downloads, Extensions, Settings
  sheets/            dialogs and drawers: filters, source settings, categories, tracking
  reader/            ReaderPage, PagedView, WebtoonView, ZoomablePage
```

### Scripted runs

`REVENANT_SCRIPT=file` runs simple commands against the window (`wait ms`,
`eval js`, `key Name`, `shot file.png`, `quit`). Combined with an offscreen GPU
context it takes screenshots without touching the desktop:

```sh
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl \
  REVENANT_SCRIPT=tour.txt ./build/revenant
```

## Credits

Fraunces and Inter (SIL OFL 1.1), Lucide icons (ISC); licence texts are in
`assets/fonts/`. Suwayomi-Server is MPL-2.0 and is downloaded at runtime, not
bundled.
