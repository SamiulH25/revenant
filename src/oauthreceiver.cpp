#include "oauthreceiver.h"

#include <QHostAddress>
#include <QTcpServer>
#include <QTcpSocket>
#include <QUrl>
#include <QUrlQuery>

namespace {
const char *kPath = "/tracker/login/oauth";

QByteArray page(const QByteArray &body)
{
    return "<!doctype html><meta charset=utf-8><title>Revenant</title>"
           "<body style=\"background:#0c0c11;color:#eeebf3;font:16px system-ui;display:grid;"
           "place-items:center;height:100vh;margin:0\">"
           + body + "</body>";
}

// Moves a #fragment into the query so the next request carries it.
const QByteArray kBounce = page(
    "<p>Finishing sign-in…</p><script>"
    "if(location.hash.length>1){location.replace(location.pathname+'?'+"
    "(location.search.length>1?location.search.slice(1)+'&':'')+location.hash.slice(1)+'&bounced=1')}"
    "else{location.replace(location.pathname+location.search+(location.search?'&':'?')+'bounced=1')}"
    "</script>");

const QByteArray kDone = page("<p>Got it. You can close this tab and return to Revenant.</p>");
}

OAuthReceiver::OAuthReceiver(QObject *parent)
    : QObject(parent)
    , m_server(new QTcpServer(this))
{
    connect(m_server, &QTcpServer::newConnection, this, &OAuthReceiver::handle);
}

QString OAuthReceiver::redirectUrl()
{
    if (!m_server->isListening() && !m_server->listen(QHostAddress::LocalHost, 0))
        return {};
    return QStringLiteral("http://127.0.0.1:%1%2").arg(m_server->serverPort()).arg(QLatin1String(kPath));
}

void OAuthReceiver::handle()
{
    while (QTcpSocket *socket = m_server->nextPendingConnection()) {
        connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QTcpSocket::readyRead, this, [this, socket] {
            const QByteArray head = socket->readAll();
            // "GET /path?query HTTP/1.1"
            const QList<QByteArray> requestLine = head.left(head.indexOf("\r\n")).split(' ');
            const QByteArray target = requestLine.size() >= 2 ? requestLine.at(1) : QByteArray();
            const QUrl url(QStringLiteral("http://127.0.0.1:%1").arg(m_server->serverPort()) + QString::fromUtf8(target));

            QByteArray body;
            QByteArray status = "200 OK";
            if (url.path() != QLatin1String(kPath)) {
                status = "404 Not Found";
                body = page("<p>Not found</p>");
            } else if (!QUrlQuery(url).hasQueryItem(QStringLiteral("bounced"))) {
                body = kBounce;
            } else {
                body = kDone;
                emit received(url.toString(QUrl::FullyEncoded));
            }
            socket->write("HTTP/1.1 " + status + "\r\nContent-Type: text/html; charset=utf-8\r\n"
                          "Cache-Control: no-store\r\nConnection: close\r\nContent-Length: "
                          + QByteArray::number(body.size()) + "\r\n\r\n" + body);
            socket->disconnectFromHost();
        });
    }
}
