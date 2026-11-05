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

- **Library** with a cinematic Continue reading hero that cycles through what
  you're in the middle of, categories, unread badges and series progress,
  sorting and filtering (cards glide to their new places), and library
  updates (manual or scheduled).
- **Discover**: a spotlight and Popular / Latest shelves for your pinned and
  recent sources, one search box that asks every source at once and ranks
  the top matches across them, and a quick-look drawer to skim titles
  without leaving the page. Narrow a single source with its own filters
  (tags, sort, status...); configurable sources have a settings sheet.
- **Command palette** (Ctrl+K or /): jump to anything in your library, a
  source or a page, or search everywhere.
- **Extensions** from the Keiyoushi catalog: install, update, remove.
- **Webtoons** read as one continuous strip: chapters join end to end as you
  scroll, each finished chapter is marked read on the way, and resuming
  lands exactly where you left off. Long-strip series are recognised (from
  their tags or the shape of their pages) and open in Webtoon mode; the
  reading mode is remembered per series, on the server.
- **Reader** with Manga (right-to-left), Comic and Webtoon modes, a real
  page-curl turn you can grab and peel (or slide / fade), ambient light that
  tints the margins with the page's colours, two-page spreads, smooth zoom,
  page previews on the scrubber, autoplay and webtoon autoscroll, saved
  progress, and a chapter-complete card to carry you into the next one.
- **Downloads** for offline reading, with a live queue and per-title storage.
- **Tracking** with AniList, MyAnimeList, Kitsu, MangaUpdates, Shikimori and
  Bangumi: link titles, and progress syncs as you finish chapters.

## Requirements

- Qt 6.9+ (Base, Declarative, ShaderTools, ImageFormats for WebP covers)
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
| M | Cycle Manga (RTL) → Comic (LTR) → Webtoon, for this series |
| K / J / L | Autoplay (autoscroll in Webtoon) / slower / faster |
| C / , | Chapter list / reading settings |
| 2 / O | Toggle two-page spreads / shift the pairing by one page |
| Z, Ctrl+wheel, double-click centre | Zoom (Webtoon: fill the window / widen or narrow the strip) |
| F / F11 | Fullscreen |
| H / Tab | Toggle the reader controls |
| Esc / Q / Backspace | Close the reader |

Clicking the left or right third of a page turns it; the middle toggles the
controls. Drag a page sideways to peel it over by hand. App-wide: Ctrl+K or /
opens the command palette, Ctrl+1–5 switch sections, Ctrl+, opens settings,
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
shaders/
  curl.frag          page-curl turn (compiled to .qsb at build time)
qml/
  Api.qml            named GraphQL operations
  Theme.qml Prefs.qml Icons.qml
  components/        design-system pieces (MangaCard, TopBar, GlassPanel, CommandPalette,
                     PeekDrawer, CoverFlight, Backdrop, Aurora, ...)
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

### Development helpers

- `tools/make-sample-library.py` draws a library of original sample manga
  (covers, pages, webtoon strips) into Suwayomi's Local source, and with
  `--library` adds them to a running server's library with categories and
  reading progress, so every screen has something real to show.
- `tools/dev-server.sh` runs Suwayomi-Server in the foreground with
  Revenant's settings; the app attaches to it instead of starting its own.
- `tools/shoot.sh script.txt` runs a `REVENANT_SCRIPT` headless under Xvfb.
- `tools/cloud-setup.sh` provisions a fresh Ubuntu container (Qt from
  conda-forge, Xvfb, the server jar).
