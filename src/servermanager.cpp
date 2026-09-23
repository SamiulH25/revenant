#include "servermanager.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

namespace {
constexpr int kPort = 4577;
constexpr int kMaxLogLines = 400;
constexpr int kPollIntervalMs = 750;
constexpr int kMaxPollAttempts = 240; // ~3 minutes; first boot unpacks a lot
const char *kReleaseApi = "https://api.github.com/repos/Suwayomi/Suwayomi-Server/releases/latest";
}

ServerManager::ServerManager(QObject *parent)
    : QObject(parent)
    , m_net(new QNetworkAccessManager(this))
{
    m_pollTimer.setInterval(kPollIntervalMs);
    m_pollTimer.setSingleShot(true);
    connect(&m_pollTimer, &QTimer::timeout, this, &ServerManager::pollUntilReady);
}

ServerManager::~ServerManager()
{
    stop();
}

QUrl ServerManager::baseUrl() const
{
    return QUrl(QStringLiteral("http://127.0.0.1:%1").arg(kPort));
}

QString ServerManager::dataDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

QString ServerManager::jarPath() const
{
    return dataDir() + QStringLiteral("/server/Suwayomi-Server.jar");
}

QString ServerManager::findJava() const
{
    const QString override = qEnvironmentVariable("REVENANT_JAVA");
    if (!override.isEmpty() && QFileInfo(override).isExecutable())
        return override;
    const QString home = qEnvironmentVariable("JAVA_HOME");
    if (!home.isEmpty()) {
        const QString candidate = home + QStringLiteral("/bin/java");
        if (QFileInfo(candidate).isExecutable())
            return candidate;
    }
    return QStandardPaths::findExecutable(QStringLiteral("java"));
}

void ServerManager::setState(State state, const QString &text)
{
    m_state = state;
    m_statusText = text;
    emit stateChanged();
}

void ServerManager::setProgress(qreal progress)
{
    m_progress = progress;
    emit progressChanged();
}

void ServerManager::appendLog(const QString &line)
{
    m_log.append(line);
    if (m_log.size() > kMaxLogLines)
        m_log.remove(0, m_log.size() - kMaxLogLines);
    emit logChanged();
}

void ServerManager::fail(const QString &reason)
{
    appendLog(QStringLiteral("[revenant] ") + reason);
    setState(Failed, reason);
}

void ServerManager::start()
{
    if (m_state == Probing || m_state == Downloading || m_state == Starting || m_state == Ready)
        return;
    setProgress(0);
    setState(Probing, tr("Looking for a running server"));
    probe([this](bool ok) {
        if (ok) {
            m_attached = true;
            appendLog(QStringLiteral("[revenant] Attached to existing server on port %1").arg(kPort));
            setState(Ready, tr("Connected"));
            emit ready();
            return;
        }
        ensureJar();
    });
}

void ServerManager::restart()
{
    stop();
    m_attached = false;
    setState(Idle, QString());
    start();
}

void ServerManager::stop()
{
    m_pollTimer.stop();
    if (!m_process)
        return;
    m_process->disconnect(this);
    if (m_process->state() != QProcess::NotRunning) {
        m_process->terminate();
        if (!m_process->waitForFinished(8000))
            m_process->kill();
        m_process->waitForFinished(2000);
    }
    m_process->deleteLater();
    m_process = nullptr;
}

void ServerManager::probe(std::function<void(bool ok)> done)
{
    QNetworkRequest request(baseUrl().resolved(QUrl(QStringLiteral("/api/graphql"))));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setTransferTimeout(3000);
    const QByteArray body = R"({"query":"{aboutServer{name version}}"})";
    QNetworkReply *reply = m_net->post(request, body);
    connect(reply, &QNetworkReply::finished, this, [this, reply, done] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            done(false);
            return;
        }
        const QJsonObject about = QJsonDocument::fromJson(reply->readAll())
                                      .object()[QStringLiteral("data")]
                                      .toObject()[QStringLiteral("aboutServer")]
                                      .toObject();
        const bool ok = about[QStringLiteral("name")].toString().contains(QStringLiteral("Suwayomi"));
        if (ok)
            m_version = about[QStringLiteral("version")].toString();
        done(ok);
    });
}

void ServerManager::ensureJar()
{
    if (QFileInfo::exists(jarPath())) {
        launch();
        return;
    }
    fetchRelease();
}

void ServerManager::fetchRelease()
{
    setState(Downloading, tr("Finding the latest Suwayomi-Server release"));
    QNetworkRequest request{QUrl(QString::fromLatin1(kReleaseApi))};
    request.setRawHeader("Accept", "application/vnd.github+json");
    QNetworkReply *reply = m_net->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            fail(tr("Could not reach GitHub to download the server: %1").arg(reply->errorString()));
            return;
        }
        const QJsonArray assets = QJsonDocument::fromJson(reply->readAll())
                                      .object()[QStringLiteral("assets")]
                                      .toArray();
        static const QRegularExpression jarName(QStringLiteral(R"(^Suwayomi-Server-v[\d.]+\.jar$)"));
        QUrl jarUrl, checksumsUrl;
        QString assetName;
        for (const QJsonValue &value : assets) {
            const QJsonObject asset = value.toObject();
            const QString name = asset[QStringLiteral("name")].toString();
            const QUrl url(asset[QStringLiteral("browser_download_url")].toString());
            if (jarName.match(name).hasMatch()) {
                jarUrl = url;
                assetName = name;
            } else if (name == QStringLiteral("Checksums.sha256")) {
                checksumsUrl = url;
            }
        }
        if (!jarUrl.isValid() || !checksumsUrl.isValid()) {
            fail(tr("The latest server release has no jar or checksum file"));
            return;
        }
        downloadJar(jarUrl, checksumsUrl, assetName);
    });
}

void ServerManager::downloadJar(const QUrl &jarUrl, const QUrl &checksumsUrl, const QString &assetName)
{
    QNetworkReply *sums = m_net->get(QNetworkRequest(checksumsUrl));
    connect(sums, &QNetworkReply::finished, this, [=, this] {
        sums->deleteLater();
        QByteArray expected;
        for (const QByteArray &line : sums->readAll().split('\n')) {
            const QList<QByteArray> parts = line.simplified().split(' ');
            if (parts.size() == 2 && parts[1] == assetName.toUtf8())
                expected = parts[0].toLower();
        }
        if (expected.isEmpty()) {
            fail(tr("No checksum published for %1").arg(assetName));
            return;
        }

        QDir().mkpath(QFileInfo(jarPath()).absolutePath());
        auto *file = new QSaveFile(jarPath(), this);
        if (!file->open(QIODevice::WriteOnly)) {
            fail(tr("Cannot write %1").arg(jarPath()));
            delete file;
            return;
        }
        auto *hash = new QCryptographicHash(QCryptographicHash::Sha256);
        setState(Downloading, tr("Downloading %1").arg(assetName));
        appendLog(QStringLiteral("[revenant] Downloading ") + jarUrl.toString());

        QNetworkReply *reply = m_net->get(QNetworkRequest(jarUrl));
        connect(reply, &QNetworkReply::readyRead, this, [reply, file, hash] {
            const QByteArray chunk = reply->readAll();
            hash->addData(chunk);
            file->write(chunk);
        });
        connect(reply, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
            if (total > 0)
                setProgress(qreal(got) / qreal(total));
        });
        connect(reply, &QNetworkReply::finished, this, [=, this] {
            reply->deleteLater();
            const QByteArray chunk = reply->readAll();
            hash->addData(chunk);
            file->write(chunk);
            const QByteArray actual = hash->result().toHex();
            delete hash;
            if (reply->error() != QNetworkReply::NoError) {
                file->cancelWriting();
                file->deleteLater();
                fail(tr("Server download failed: %1").arg(reply->errorString()));
                return;
            }
            if (actual != expected) {
                file->cancelWriting();
                file->deleteLater();
                fail(tr("Server download failed its checksum check"));
                return;
            }
            file->commit();
            file->deleteLater();
            appendLog(QStringLiteral("[revenant] Verified sha256 ") + QString::fromLatin1(actual));
            launch();
        });
    });
}

void ServerManager::launch()
{
    const QString java = findJava();
    if (java.isEmpty()) {
        fail(tr("Java 21 or newer is required. Install a JDK or set REVENANT_JAVA."));
        return;
    }

    const QString root = dataDir() + QStringLiteral("/data");
    QDir().mkpath(root);
    const auto prop = [](const char *key, const QString &value) {
        return QStringLiteral("-Dsuwayomi.tachidesk.config.server.%1=%2").arg(QLatin1String(key), value);
    };
    const QStringList args{
        QStringLiteral("-Djava.awt.headless=true"),
        prop("rootDir", root),
        prop("ip", QStringLiteral("127.0.0.1")),
        prop("port", QString::number(kPort)),
        prop("webUIEnabled", QStringLiteral("false")),
        prop("initialOpenInBrowserEnabled", QStringLiteral("false")),
        prop("systemTrayEnabled", QStringLiteral("false")),
        QStringLiteral("-jar"),
        jarPath(),
    };

    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    m_process->setWorkingDirectory(QFileInfo(jarPath()).absolutePath());
    connect(m_process, &QProcess::readyReadStandardOutput, this, [this] {
        m_stdoutBuffer += m_process->readAllStandardOutput();
        qsizetype newline;
        while ((newline = m_stdoutBuffer.indexOf('\n')) >= 0) {
            appendLog(QString::fromUtf8(m_stdoutBuffer.left(newline)).trimmed());
            m_stdoutBuffer.remove(0, newline + 1);
        }
    });
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            fail(tr("Could not start Java: %1").arg(m_process->errorString()));
    });
    connect(m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus) {
        m_pollTimer.stop();
        fail(tr("The server exited (code %1)").arg(code));
    });

    setState(Starting, tr("Starting the extension server"));
    appendLog(QStringLiteral("[revenant] %1 %2").arg(java, args.join(QLatin1Char(' '))));
    m_process->start(java, args);
    m_pollAttempts = 0;
    m_pollTimer.start();
}

void ServerManager::pollUntilReady()
{
    if (m_state != Starting)
        return;
    probe([this](bool ok) {
        if (m_state != Starting)
            return;
        if (ok) {
            setState(Ready, tr("Connected"));
            emit ready();
            return;
        }
        if (++m_pollAttempts >= kMaxPollAttempts) {
            fail(tr("The server did not come up in time"));
            stop();
            return;
        }
        m_pollTimer.start();
    });
}
