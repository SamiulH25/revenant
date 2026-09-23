cmake_minimum_required(VERSION 3.21)

project(Revenant VERSION 0.1.0 LANGUAGES CXX)
include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Network Quick QuickControls2 Concurrent)

qt_standard_project_setup(REQUIRES 6.5)
qt_policy(SET QTP0004 NEW)

qt_add_executable(revenant
    src/main.cpp
    src/servermanager.h src/servermanager.cpp
    src/graphqlclient.h src/graphqlclient.cpp
    src/imagecache.h src/imagecache.cpp
    src/keyedlistmodel.h src/keyedlistmodel.cpp
    src/devscript.h src/devscript.cpp
    src/oauthreceiver.h src/oauthreceiver.cpp
)

set(QML_FILES
    qml/Main.qml
    qml/Theme.qml
    qml/Icons.qml
    qml/Api.qml
    qml/Prefs.qml
    qml/components/Icon.qml
    qml/components/IconButton.qml
    qml/components/PillButton.qml
    qml/components/NavRail.qml
    qml/components/Cover.qml
    qml/components/MangaCard.qml
    qml/components/SearchField.qml
    qml/components/Chip.qml
    qml/components/Spinner.qml
    qml/components/EmptyState.qml
    qml/components/Toast.qml
    qml/components/SectionHeader.qml
    qml/components/Ambient.qml
    qml/components/Segmented.qml
    qml/components/Glow.qml
    qml/components/Dropdown.qml
    qml/components/TextBox.qml
    qml/components/Toggle.qml
    qml/components/Sheet.qml
    qml/components/PopMenu.qml
    qml/sheets/FilterItem.qml
    qml/sheets/FilterSheet.qml
    qml/sheets/SourceSettingsSheet.qml
    qml/sheets/CategoriesSheet.qml
    qml/sheets/MangaCategoriesSheet.qml
    qml/sheets/TrackingSheet.qml
    qml/sheets/TrackerLoginSheet.qml
    qml/pages/BootPage.qml
    qml/pages/LibraryPage.qml
    qml/pages/BrowsePage.qml
    qml/pages/SourcePage.qml
    qml/pages/ExtensionsPage.qml
    qml/pages/MangaPage.qml
    qml/pages/HistoryPage.qml
    qml/pages/SettingsPage.qml
    qml/pages/DownloadsPage.qml
    qml/reader/ReaderPage.qml
    qml/reader/PagedView.qml
    qml/reader/WebtoonView.qml
    qml/reader/ZoomablePage.qml
)

set_source_files_properties(qml/Theme.qml qml/Icons.qml qml/Api.qml qml/Prefs.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(revenant
    URI Revenant
    QML_FILES ${QML_FILES}
    RESOURCES
        assets/fonts/Fraunces.ttf
        assets/fonts/Fraunces-Italic.ttf
        assets/fonts/Inter.ttf
        assets/fonts/lucide.ttf
        assets/icons/revenant.svg
)

target_include_directories(revenant PRIVATE src)

target_link_libraries(revenant PRIVATE
    Qt6::Core Qt6::Gui Qt6::Network Qt6::Quick Qt6::QuickControls2 Qt6::Concurrent)

target_compile_definitions(revenant PRIVATE PROJECT_VERSION="${PROJECT_VERSION}")

install(TARGETS revenant RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES dist/revenant.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES assets/icons/revenant.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
