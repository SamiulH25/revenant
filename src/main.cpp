#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>

#include "devscript.h"
#include "graphqlclient.h"
#include "imagecache.h"
#include "servermanager.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("revenant"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Revenant"));
    QGuiApplication::setApplicationVersion(QStringLiteral(PROJECT_VERSION));
    QGuiApplication::setDesktopFileName(QStringLiteral("revenant"));
    QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/qt/qml/Revenant/assets/icons/revenant.svg")));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    for (const char *font : {"Inter.ttf", "Fraunces.ttf", "Fraunces-Italic.ttf", "lucide.ttf"})
        QFontDatabase::addApplicationFont(QStringLiteral(":/qt/qml/Revenant/assets/fonts/") + QLatin1String(font));
    QFont base(QStringLiteral("Inter"));
    base.setPixelSize(14);
    base.setHintingPreference(QFont::PreferNoHinting);
    QGuiApplication::setFont(base);

    QQmlApplicationEngine engine;

    // The engine owns the singletons; wire them up before any QML loads.
    auto *server = engine.singletonInstance<ServerManager *>("Revenant", "ServerManager");
    auto *gql = engine.singletonInstance<GraphQLClient *>("Revenant", "Gql");
    auto *images = engine.singletonInstance<ImageCache *>("Revenant", "ImageCache");
    const QUrl serverUrl = server->baseUrl();
    gql->setEndpoint(serverUrl.resolved(QUrl(QStringLiteral("/api/graphql"))));
    images->setBaseUrl(serverUrl);

    engine.addImageProvider(QStringLiteral("cover"), new CoverImageProvider);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    QObject::connect(&app, &QCoreApplication::aboutToQuit, server, &ServerManager::stop);

    engine.loadFromModule("Revenant", "Main");
    server->start();
    DevScript::startIfRequested(&engine);

    return app.exec();
}
