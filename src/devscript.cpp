#include "devscript.h"

#include <QCoreApplication>
#include <QFile>
#include <QKeyEvent>
#include <QMetaEnum>
#include <QMouseEvent>
#include <QQmlApplicationEngine>
#include <QQmlExpression>
#include <QQuickWindow>
#include <QTimer>
#include <QtQml/qqmlcontext.h>

void DevScript::startIfRequested(QQmlApplicationEngine *engine)
{
    const QString path = qEnvironmentVariable("REVENANT_SCRIPT");
    if (path.isEmpty())
        return;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning("REVENANT_SCRIPT: cannot open %s", qPrintable(path));
        return;
    }
    QStringList lines;
    for (const QByteArray &line : file.readAll().split('\n')) {
        const QString trimmed = QString::fromUtf8(line).trimmed();
        if (!trimmed.isEmpty() && !trimmed.startsWith(QLatin1Char('#')))
            lines.append(trimmed);
    }
    auto *script = new DevScript(engine, lines);
    QTimer::singleShot(0, script, &DevScript::step);
}

DevScript::DevScript(QQmlApplicationEngine *engine, QStringList lines)
    : QObject(engine)
    , m_engine(engine)
    , m_lines(std::move(lines))
{
    m_clock.start();
}

void DevScript::mouse(QWindow *window, QEvent::Type type, QPointF pos)
{
    Qt::MouseButton button = Qt::NoButton;
    if (type == QEvent::MouseButtonPress) {
        button = Qt::LeftButton;
        m_buttons |= Qt::LeftButton;
    } else if (type == QEvent::MouseButtonRelease) {
        button = Qt::LeftButton;
        m_buttons &= ~Qt::LeftButton;
    }
    QMouseEvent event(type, pos, window->mapToGlobal(pos), button, m_buttons, Qt::NoModifier);
    // Pointer handlers work out velocity from timestamps.
    event.setTimestamp(quint64(m_clock.elapsed()));
    QCoreApplication::sendEvent(window, &event);
}

void DevScript::step()
{
    if (m_lines.isEmpty())
        return;
    const QString line = m_lines.takeFirst();
    const QString command = line.section(QLatin1Char(' '), 0, 0);
    const QString arg = line.section(QLatin1Char(' '), 1);

    auto *window = m_engine->rootObjects().isEmpty()
        ? nullptr
        : qobject_cast<QQuickWindow *>(m_engine->rootObjects().first());
    int delay = 0;

    if (command == QLatin1String("wait")) {
        delay = arg.toInt();
    } else if (command == QLatin1String("eval") && window) {
        QQmlExpression expression(qmlContext(window), window, arg);
        expression.evaluate();
        if (expression.hasError())
            qWarning("REVENANT_SCRIPT eval: %s", qPrintable(expression.error().toString()));
    } else if (command == QLatin1String("key") && window) {
        bool ok = false;
        const int key = QMetaEnum::fromType<Qt::Key>().keyToValue(("Key_" + arg).toLatin1(), &ok);
        if (ok) {
            QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier);
            QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier);
            QCoreApplication::sendEvent(window, &press);
            QCoreApplication::sendEvent(window, &release);
        }
    } else if (window && (command == QLatin1String("move") || command == QLatin1String("press")
                          || command == QLatin1String("release") || command == QLatin1String("click"))) {
        const QStringList n = arg.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        const QPointF pos(n.value(0).toDouble(), n.value(1).toDouble());
        if (command == QLatin1String("move")) {
            mouse(window, QEvent::MouseMove, pos);
        } else if (command == QLatin1String("press")) {
            mouse(window, QEvent::MouseButtonPress, pos);
        } else if (command == QLatin1String("release")) {
            mouse(window, QEvent::MouseButtonRelease, pos);
        } else {
            mouse(window, QEvent::MouseButtonPress, pos);
            mouse(window, QEvent::MouseButtonRelease, pos);
        }
    } else if (command == QLatin1String("glide")) {
        // Expands into small timed moves, queued ahead of the rest.
        const QStringList n = arg.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        const double x1 = n.value(0).toDouble(), y1 = n.value(1).toDouble();
        const double x2 = n.value(2).toDouble(), y2 = n.value(3).toDouble();
        const int ms = qMax(16, n.value(4).toInt());
        const int steps = qMax(2, ms / 16);
        QStringList moves;
        for (int i = 1; i <= steps; ++i) {
            const double t = double(i) / steps;
            moves << QStringLiteral("move %1 %2").arg(x1 + (x2 - x1) * t).arg(y1 + (y2 - y1) * t)
                  << QStringLiteral("wait 16");
        }
        m_lines = moves + m_lines;
    } else if (command == QLatin1String("shot") && window) {
        window->grabWindow().save(arg);
    } else if (command == QLatin1String("quit")) {
        QCoreApplication::quit();
        return;
    }
    QTimer::singleShot(delay, this, &DevScript::step);
}
