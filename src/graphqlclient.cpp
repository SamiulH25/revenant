#include "graphqlclient.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QtQml/qqmlengine.h>

namespace {
// Source requests go out to third-party sites through the server, and some
// sit behind Cloudflare challenges, so allow them plenty of time.
constexpr int kTimeoutMs = 180000;
}

GraphQLClient::GraphQLClient(QObject *parent)
    : QObject(parent)
    , m_net(new QNetworkAccessManager(this))
{
}

void GraphQLClient::setEndpoint(const QUrl &endpoint)
{
    if (m_endpoint == endpoint)
        return;
    m_endpoint = endpoint;
    emit endpointChanged();
}

void GraphQLClient::request(const QString &query, const QVariantMap &variables, const QJSValue &callback)
{
    QNetworkRequest request(m_endpoint);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setTransferTimeout(kTimeoutMs);

    QJsonObject body{{QStringLiteral("query"), query}};
    if (!variables.isEmpty())
        body[QStringLiteral("variables")] = QJsonObject::fromVariantMap(variables);

    ++m_inFlight;
    emit inFlightChanged();

    QNetworkReply *reply = m_net->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply, callback] {
        reply->deleteLater();
        --m_inFlight;
        emit inFlightChanged();

        const QByteArray payload = reply->readAll();
        const QJsonObject json = QJsonDocument::fromJson(payload).object();

        QString error;
        const QJsonArray errors = json[QStringLiteral("errors")].toArray();
        if (!errors.isEmpty())
            error = errors.first().toObject()[QStringLiteral("message")].toString();
        else if (reply->error() != QNetworkReply::NoError)
            error = reply->errorString();
        else if (json.isEmpty())
            error = tr("Empty response from server");

        QJSEngine *engine = qjsEngine(this);
        if (!callback.isCallable() || !engine)
            return;
        const QJSValue data = engine->toScriptValue(json[QStringLiteral("data")].toObject().toVariantMap());
        QJSValue(callback).call({QJSValue(error), data});
    });
}
