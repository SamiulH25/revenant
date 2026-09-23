#pragma once

#include <QColor>
#include <QHash>
#include <QImage>
#include <QJSValue>
#include <QObject>
#include <QQuickAsyncImageProvider>
#include <QUrl>
#include <QtQml/qqmlregistration.h>
#include <functional>

class QNetworkAccessManager;

// Server thumbnails are full-size source images (often several MB of PNG).
// This cache fetches each one once, stores a downscaled JPEG on disk per width
// bucket, and serves it to QML through image://cover/<server path>.
class ImageCache : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QUrl baseUrl READ baseUrl WRITE setBaseUrl NOTIFY baseUrlChanged)

public:
    using Callback = std::function<void(const QImage &image, const QString &error)>;

    explicit ImageCache(QObject *parent = nullptr);

    // The engine-owned singleton, for the image provider.
    static ImageCache *instance();

    QUrl baseUrl() const { return m_baseUrl; }
    void setBaseUrl(const QUrl &url);

    // Must be called on the cache's thread. The callback runs on it too.
    void fetch(const QString &path, int width, Callback callback);

    // Resolves callback(color) with a vivid accent from the cover, or an
    // invalid color (undefined in QML) when the cover is essentially grey.
    Q_INVOKABLE void accent(const QString &path, const QJSValue &callback);
    Q_INVOKABLE qint64 diskUsage() const;
    Q_INVOKABLE void clear();

signals:
    void baseUrlChanged();

private:
    struct Pending {
        int width;
        Callback callback;
    };

    QString cacheDir() const;
    QString cacheFile(const QString &path, int width) const;
    void deliver(const QString &path, const QByteArray &bytes, const QString &error);

    QNetworkAccessManager *m_net;
    QUrl m_baseUrl;
    QHash<QString, QList<Pending>> m_waiting; // path -> requests sharing one download
    QHash<QString, QColor> m_accents;
};

class CoverImageProvider : public QQuickAsyncImageProvider
{
public:
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;
};
