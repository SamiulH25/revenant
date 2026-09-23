#include "devscript.h"

#include <QCoreApplication>
#include <QFile>
#include <QKeyEvent>
#include <QMetaEnum>
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
    } else if (command == QLatin1String("shot") && window) {
        window->grabWindow().save(arg);
    } else if (command == QLatin1String("quit")) {
        QCoreApplication::quit();
        return;
    }
    QTimer::singleShot(delay, this, &DevScript::step);
}
