cmake_minimum_required(VERSION 3.21)
project(copper-dashboard VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Network Qml Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(copper-dashboard src/main.cpp)

# Theme.qml is a singleton. The property must be set BEFORE qt_add_qml_module().
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(copper-dashboard
    URI CopperDashboard
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/components/Tile.qml
        qml/components/Card.qml
        qml/components/Meter.qml
        qml/components/StatusDot.qml
        qml/components/T.qml
        qml/components/Dot.qml
        qml/components/Bar.qml
        qml/components/FixBtn.qml
        qml/components/KV.qml
        qml/components/Sub.qml
        qml/components/Panel.qml
        qml/components/Sheet.qml
        qml/components/ThinScroll.qml
        qml/panels/AttentionPanel.qml
        qml/panels/HostPanel.qml
        qml/panels/ThermalPanel.qml
        qml/panels/JailsPanel.qml
        qml/panels/StoragePanel.qml
        qml/panels/MediaPanel.qml
        qml/panels/ServicesPanel.qml
        qml/panels/RoutinePanel.qml
        qml/pages/DashboardPage.qml
        qml/pages/AppsPage.qml
        qml/pages/MediaPage.qml
        qml/pages/NetworkPage.qml
        qml/pages/SystemPage.qml
        qml/pages/UpdatesPage.qml
    RESOURCES
        assets/logo.png
        assets/background.jpg
        assets/fonts/Rajdhani-Regular.ttf
        assets/fonts/Rajdhani-Bold.ttf
        assets/fonts/Orbitron.ttf
    SOURCES
        src/SystemInfo.h src/SystemInfo.cpp
        src/AppCatalog.h src/AppCatalog.cpp
        src/MediaStatus.h src/MediaStatus.cpp
        src/Backend.h src/Backend.cpp
)

target_include_directories(copper-dashboard PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_link_libraries(copper-dashboard PRIVATE
    Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml Qt6::Quick Qt6::QuickControls2)

include(GNUInstallDirs)
install(TARGETS copper-dashboard RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/copper-dashboard.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES data/copper-dashboard-autostart.desktop
        DESTINATION etc/xdg/autostart RENAME copper-dashboard.desktop)
foreach(sz 48 64 128 256)
    install(FILES assets/icon-${sz}.png
            DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/${sz}x${sz}/apps
            RENAME copper-dashboard.png)
endforeach()
