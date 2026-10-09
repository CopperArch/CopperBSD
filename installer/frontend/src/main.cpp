#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QIcon>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("CopperArch Installer"));
    app.setOrganizationName(QStringLiteral("CopperArch"));
    app.setWindowIcon(QIcon(QStringLiteral(":/qt/qml/CopperArch/assets/logo.png")));

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed,
        &app, []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    // URI + root type registered by qt_add_qml_module (URI "CopperArch").
    engine.loadFromModule("CopperArch", "Main");

    return app.exec();
}
