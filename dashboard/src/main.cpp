#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#ifdef COPPER_HAVE_WEBENGINE
#include <QtWebEngineQuick>
#endif

#include "AppCatalog.h"
#include "Backend.h"
#include "MediaStatus.h"
#include "SystemInfo.h"

int main(int argc, char *argv[])
{
#ifdef COPPER_HAVE_WEBENGINE
    // The terminal dock is a web view onto ttyd; the engine has to be set up
    // before the application object exists.
    QtWebEngineQuick::initialize();
#endif
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("copper-dashboard"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("CopperBSD Dashboard"));
    QGuiApplication::setOrganizationName(QStringLiteral("CopperBSD"));
    QGuiApplication::setDesktopFileName(QStringLiteral("copper-dashboard"));
    QGuiApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("copper-dashboard")));

    // Use the desktop's native style (qqc2-desktop-style) under Plasma; the
    // org.kde.desktop style is what Kirigami expects. Fall back to Basic so
    // the dashboard still launches on a non-KDE session.
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE"))
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    SystemInfo system;
    AppCatalog apps;
    MediaStatus media;
    Backend dash;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("sys"), &system);
    engine.rootContext()->setContextProperty(QStringLiteral("apps"), &apps);
    engine.rootContext()->setContextProperty(QStringLiteral("media"), &media);
    engine.rootContext()->setContextProperty(QStringLiteral("dash"), &dash);
    // Set with COPPER_DOCK_WIDTH=<percent>; lets a test or a screenshot start
    // with the terminal dock open without touching the saved setting.
    engine.rootContext()->setContextProperty(QStringLiteral("startDockWidth"),
                                             qEnvironmentVariableIntValue("COPPER_DOCK_WIDTH"));

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("CopperDashboard", "Main");
    return app.exec();
}
