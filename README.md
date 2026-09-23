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

`cmake --install build` installs the binary and a desktop entry.

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
| Z, Ctrl+wheel, double-click centre | Zoom |
| F / F11 | Fullscreen |
| H / Tab | Toggle the reader controls |
| Esc / Q / Backspace | Close the reader |

Clicking the left or right third of a page turns it; the middle toggles the
controls. App-wide: Ctrl+1–4 switch sections, Ctrl+, opens settings,
Ctrl+F focuses search, Ctrl+R updates the library, Alt+← / mouse back goes back.

## Layout

```
src/
  servermanager.*    Suwayomi sidecar: Java lookup, jar download + checksum, launch, shutdown
  graphqlclient.*    GraphQL transport exposed to QML as the Gql singleton
  imagecache.*       image://cover provider: downscaled on-disk covers + cover accent colours
  keyedlistmodel.*   list model that diffs updates by key (keeps scroll position)
  devscript.*        REVENANT_SCRIPT automation for screenshots and smoke tests
qml/
  Api.qml            named GraphQL operations
  Theme.qml Prefs.qml Icons.qml
  components/        design-system pieces (Cover, MangaCard, Segmented, Glow, ...)
  pages/             Library, Browse, Source, Manga, History, Extensions, Settings
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
