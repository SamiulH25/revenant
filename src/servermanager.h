#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class QNetworkAccessManager;
class QNetworkReply;

// Owns the Suwayomi-Server sidecar: finds Java, downloads and verifies the
// server jar on first run, launches it bound to localhost, and shuts it down
// with the app. If a server is already answering on the port, it attaches to
// that one instead of spawning a second.
class ServerManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY stateChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QUrl baseUrl READ baseUrl CONSTANT)
    Q_PROPERTY(QString version READ version NOTIFY stateChanged)
    Q_PROPERTY(bool attached READ attached NOTIFY stateChanged)
    Q_PROPERTY(QStringList log READ log NOTIFY logChanged)
    Q_PROPERTY(QString dataDir READ dataDir CONSTANT)

public:
    enum State { Idle, Probing, Downloading, Starting, Ready, Failed };
    Q_ENUM(State)

    explicit ServerManager(QObject *parent = nullptr);
    ~ServerManager() override;

    State state() const { return m_state; }
    QString statusText() const { return m_statusText; }
    qreal progress() const { return m_progress; }
    QUrl baseUrl() const;
    QString version() const { return m_version; }
    bool attached() const { return m_attached; }
    QStringList log() const { return m_log; }
    QString dataDir() const;

    Q_INVOKABLE void start();
    Q_INVOKABLE void restart();
    void stop();

signals:
    void stateChanged();
    void progressChanged();
    void logChanged();
    void ready();

private:
    void setState(State state, const QString &text);
    void setProgress(qreal progress);
    void appendLog(const QString &line);
    void fail(const QString &reason);

    void probe(std::function<void(bool ok)> done);
    void ensureJar();
    void fetchRelease();
    void downloadJar(const QUrl &jarUrl, const QUrl &checksumsUrl, const QString &assetName);
    void launch();
    void pollUntilReady();

    QString jarPath() const;
    QString findJava() const;

    QNetworkAccessManager *m_net;
    QProcess *m_process = nullptr;
    QTimer m_pollTimer;
    int m_pollAttempts = 0;

    State m_state = Idle;
    QString m_statusText;
    qreal m_progress = 0;
    QString m_version;
    bool m_attached = false;
    QStringList m_log;
    QByteArray m_stdoutBuffer;
};
