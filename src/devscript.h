#pragma once

#include <QElapsedTimer>
#include <QEvent>
#include <QObject>
#include <QPointF>
#include <QStringList>

class QQmlApplicationEngine;
class QWindow;

// Development aid: when REVENANT_SCRIPT points at a file, runs its commands
// against the loaded window, one per line:
//
//   wait <ms>        pause
//   eval <js>        evaluate JS in the root window's scope (e.g. app.goTab("browse"))
//   key <key>        send a key press to the window (Qt key name without Key_, e.g. Right)
//   move <x> <y>     move the mouse (dragging if a button is down)
//   press <x> <y>    press the left button
//   release <x> <y>  release it
//   click <x> <y>    press and release
//   glide <x1> <y1> <x2> <y2> <ms>
//                    move smoothly from one point to another over ms
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
    void mouse(QWindow *window, QEvent::Type type, QPointF pos);

    QQmlApplicationEngine *m_engine;
    QStringList m_lines;
    Qt::MouseButtons m_buttons = Qt::NoButton;
    QElapsedTimer m_clock;
};
