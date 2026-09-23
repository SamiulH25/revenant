#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>

class QTcpServer;

// Catches tracker OAuth redirects on a loopback port. Suwayomi's tracker apps
// redirect to suwayomi.org, which forwards to the redirectUrl we put in the
// OAuth state; that URL points here. Tokens that arrive in the URL fragment
// (AniList) never reach an HTTP server, so the first response is a tiny page
// that re-requests with the fragment moved into the query string.
class OAuthReceiver : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(OAuth)
    QML_SINGLETON

public:
    explicit OAuthReceiver(QObject *parent = nullptr);

    // Starts listening if needed and returns the redirect URL to hand to the
    // tracker, or an empty string if no port could be opened.
    Q_INVOKABLE QString redirectUrl();

signals:
    // The complete callback URL, ready for loginTrackerOAuth.
    void received(const QString &callbackUrl);

private:
    void handle();

    QTcpServer *m_server;
};
