#pragma once

#include <QObject>
#include <QStringList>

class QQmlApplicationEngine;

// Development aid: when REVENANT_SCRIPT points at a file, runs its commands
// against the loaded window, one per line:
//
//   wait <ms>        pause
//   eval <js>        evaluate JS in the root window's scope (e.g. app.goTab("browse"))
//   key <key>        send a key press to the window (Qt key name without Key_, e.g. Right)
//   shot <file.png>  save a grab of the window
//   quit             exit the app
//
// Combined with QT_QPA_PLATFORM=offscreen this gives repeatable screenshots
// without touching the desktop.
class DevScript : public QObject
{
    Q_OBJECT

public:
    static void startIfRequested(QQmlApplicationEngine *engine);

private:
    DevScript(QQmlApplicationEngine *engine, QStringList lines);
    void step();

    QQmlApplicationEngine *m_engine;
    QStringList m_lines;
};
