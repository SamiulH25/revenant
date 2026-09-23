#include "imagecache.h"

#include <QBuffer>
#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QImageReader>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QStandardPaths>
#include <QtConcurrent/QtConcurrentRun>
#include <QtQml/qqmlengine.h>
#include <array>

namespace {
ImageCache *s_instance = nullptr;

constexpr std::array kBuckets{128, 256, 384, 512, 768, 1024};

int bucketFor(int width)
{
    for (int bucket : kBuckets) {
        if (width <= bucket)
            return bucket;
    }
    return kBuckets.back();
}

QImage decodeScaled(const QByteArray &bytes, int width)
{
    QBuffer buffer;
    buffer.setData(bytes);
    buffer.open(QIODevice::ReadOnly);
    QImageReader reader(&buffer);
    reader.setAutoTransform(true);
    const QSize size = reader.size();
    if (size.isValid() && size.width() > width)
        reader.setScaledSize(QSize(width, qRound(size.height() * (qreal(width) / size.width()))));
    return reader.read();
}

QColor accentOf(const QImage &source)
{
    const QImage image = source.scaled(32, 48, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                             .convertToFormat(QImage::Format_RGB32);
    constexpr int kBins = 24;
    std::array<double, kBins> weight{};
    std::array<std::array<double, 3>, kBins> sum{};
    double total = 0;

    for (int y = 0; y < image.height(); ++y) {
        const auto *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            const QColor c(line[x]);
            const float s = c.hsvSaturationF();
            const float v = c.valueF();
            total += 1;
            if (s < 0.22f || v < 0.22f)
                continue;
            const int hue = qMax(0, c.hsvHue());
            const int bin = (hue * kBins) / 360;
            // Favour vivid colour over the skin and paper tones that
            // dominate most covers.
            const double w = double(s) * s * v;
            weight[bin] += w;
            sum[bin][0] += c.redF() * w;
            sum[bin][1] += c.greenF() * w;
            sum[bin][2] += c.blueF() * w;
        }
    }

    int best = 0;
    for (int i = 1; i < kBins; ++i) {
        if (weight[i] > weight[best])
            best = i;
    }
    // Needs a little real colour; mostly grey or line-art covers keep the
    // app accent instead.
    if (weight[best] < total * 0.006)
        return {};

    QColor color = QColor::fromRgbF(sum[best][0] / weight[best], sum[best][1] / weight[best],
                                    sum[best][2] / weight[best]);
    return QColor::fromHsvF(color.hsvHueF(), qBound(0.45f, color.hsvSaturationF(), 0.85f),
                            qBound(0.72f, color.valueF(), 0.95f));
}

class CoverResponse : public QQuickImageResponse
{
public:
    void done(const QImage &image, const QString &error)
    {
        m_image = image;
        m_error = error;
        emit finished();
    }

    QQuickTextureFactory *textureFactory() const override
    {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }

    QString errorString() const override { return m_error; }

private:
    QImage m_image;
    QString m_error;
};
}

ImageCache::ImageCache(QObject *parent)
    : QObject(parent)
    , m_net(new QNetworkAccessManager(this))
{
    s_instance = this;
}

ImageCache *ImageCache::instance()
{
    return s_instance;
}

void ImageCache::setBaseUrl(const QUrl &url)
{
    if (m_baseUrl == url)
        return;
    m_baseUrl = url;
    emit baseUrlChanged();
}

QString ImageCache::cacheDir() const
{
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/covers");
}

QString ImageCache::cacheFile(const QString &path, int width) const
{
    const QByteArray key = QCryptographicHash::hash(path.toUtf8(), QCryptographicHash::Sha1).toHex();
    return QStringLiteral("%1/%2/%3-%4.jpg")
        .arg(cacheDir(), QString::fromLatin1(key.left(2)), QString::fromLatin1(key))
        .arg(width);
}

void ImageCache::fetch(const QString &path, int width, Callback callback)
{
    const int bucket = bucketFor(width);
    const QString file = cacheFile(path, bucket);
    if (QFile::exists(file)) {
        QtConcurrent::run([file] { return QImage(file); })
            .then(this, [callback](const QImage &image) {
                callback(image, image.isNull() ? QStringLiteral("Corrupt cache entry") : QString());
            });
        return;
    }

    QList<Pending> &waiters = m_waiting[path];
    waiters.append({bucket, std::move(callback)});
    if (waiters.size() > 1)
        return; // a download for this path is already running

    QNetworkRequest request(m_baseUrl.resolved(QUrl(path)));
    request.setTransferTimeout(120000);
    QNetworkReply *reply = m_net->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, path] {
        reply->deleteLater();
        const QString error = reply->error() == QNetworkReply::NoError ? QString() : reply->errorString();
        deliver(path, reply->readAll(), error);
    });
}

void ImageCache::deliver(const QString &path, const QByteArray &bytes, const QString &error)
{
    const QList<Pending> waiters = m_waiting.take(path);
    if (!error.isEmpty()) {
        for (const Pending &pending : waiters)
            pending.callback({}, error);
        return;
    }

    QHash<int, QList<Callback>> byBucket;
    for (const Pending &pending : waiters)
        byBucket[pending.width].append(pending.callback);

    for (auto it = byBucket.cbegin(); it != byBucket.cend(); ++it) {
        const int bucket = it.key();
        const QString file = cacheFile(path, bucket);
        const QList<Callback> callbacks = it.value();
        QtConcurrent::run([bytes, bucket, file] {
            QImage image = decodeScaled(bytes, bucket);
            if (!image.isNull()) {
                QDir().mkpath(file.section(QLatin1Char('/'), 0, -2));
                image.convertToFormat(QImage::Format_RGB32).save(file, "JPG", 88);
            }
            return image;
        }).then(this, [callbacks](const QImage &image) {
            const QString error = image.isNull() ? QStringLiteral("Unsupported image") : QString();
            for (const Callback &callback : callbacks)
                callback(image, error);
        });
    }
}

void ImageCache::accent(const QString &path, const QJSValue &callback)
{
    const auto resolve = [this, callback](const QColor &color) {
        QJSEngine *engine = qjsEngine(this);
        if (!callback.isCallable() || !engine)
            return;
        QJSValue(callback).call({color.isValid() ? engine->toScriptValue(color) : QJSValue()});
    };
    if (auto it = m_accents.constFind(path); it != m_accents.cend()) {
        resolve(*it);
        return;
    }
    fetch(path, 128, [this, path, resolve](const QImage &image, const QString &) {
        const QColor color = image.isNull() ? QColor() : accentOf(image);
        m_accents.insert(path, color);
        resolve(color);
    });
}

qint64 ImageCache::diskUsage() const
{
    qint64 bytes = 0;
    QDirIterator it(cacheDir(), QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext())
        bytes += it.nextFileInfo().size();
    return bytes;
}

void ImageCache::clear()
{
    QDir(cacheDir()).removeRecursively();
    m_accents.clear();
}

QQuickImageResponse *CoverImageProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    auto *response = new CoverResponse;
    const QString path = QUrl::fromPercentEncoding(id.toUtf8());
    const int width = requestedSize.width() > 0 ? requestedSize.width() : 384;
    // Responses are created on the image loader thread; the cache and its
    // network manager live on the main thread. The engine deletes the
    // response only after finished(), so the pointer stays valid until done().
    QMetaObject::invokeMethod(ImageCache::instance(), [response, path, width] {
        ImageCache::instance()->fetch(path, width, [response](const QImage &image, const QString &error) {
            response->done(image, error);
        });
    }, Qt::QueuedConnection);
    return response;
}
