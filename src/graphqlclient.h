#pragma once

#include <QJSValue>
#include <QObject>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QNetworkAccessManager;

// Minimal GraphQL transport for QML. Every call resolves exactly once through
// callback(error, data): error is an empty string on success, data is the
// response's "data" object (possibly partial when the server also reports
// errors).
class GraphQLClient : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Gql)
    QML_SINGLETON

    Q_PROPERTY(QUrl endpoint READ endpoint WRITE setEndpoint NOTIFY endpointChanged)
    Q_PROPERTY(int inFlight READ inFlight NOTIFY inFlightChanged)

public:
    explicit GraphQLClient(QObject *parent = nullptr);

    QUrl endpoint() const { return m_endpoint; }
    void setEndpoint(const QUrl &endpoint);
    int inFlight() const { return m_inFlight; }

    Q_INVOKABLE void request(const QString &query, const QVariantMap &variables, const QJSValue &callback);

signals:
    void endpointChanged();
    void inFlightChanged();

private:
    QNetworkAccessManager *m_net;
    QUrl m_endpoint;
    int m_inFlight = 0;
};
