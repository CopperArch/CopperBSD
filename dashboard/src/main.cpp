#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

#include "AppCatalog.h"
#include "Backend.h"
#include "MediaStatus.h"
#include "SystemInfo.h"

int main(int argc, char *argv[])
{
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

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("CopperDashboard", "Main");
    return app.exec();
}
