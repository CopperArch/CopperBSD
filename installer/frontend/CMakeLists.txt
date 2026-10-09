cmake_minimum_required(VERSION 3.21.1)

project(CopperArchInstaller VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Quick Qml Core)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(copperarch-installer
    src/main.cpp
)

# Theme.qml is a singleton (pragma Singleton); mark it so the module registers
# it as one rather than an instantiable type. This MUST come before
# qt_add_qml_module(): Qt reads the property when the module is declared, and
# setting it afterwards silently leaves every `Theme.xxx` undefined.
set_source_files_properties(qml/Theme.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

# Backend types are registered into the QML module via QML_ELEMENT, so their
# sources live in the module (SOURCES), not in the executable above.
qt_add_qml_module(copperarch-installer
    URI CopperArch
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/pages/Welcome.qml
        qml/pages/Locale.qml
        qml/pages/Keyboard.qml
        qml/pages/Desktop.qml
        qml/pages/Disk.qml
        qml/pages/Account.qml
        qml/pages/Summary.qml
        qml/pages/Install.qml
        qml/pages/Finish.qml
    RESOURCES
        assets/logo.png
        assets/background.jpg
    SOURCES
        src/InstallerBackend.h
        src/InstallerBackend.cpp
        src/DiskModel.h
        src/DiskModel.cpp
)

# Qt's generated qmltyperegistrations.cpp finds QML_ELEMENT headers via
# `__has_include(<DiskModel.h>)` (angle brackets, not relative to src/), so
# src/ must be on the include path for registration to resolve at all.
target_include_directories(copperarch-installer
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(copperarch-installer
    PRIVATE
        Qt6::Quick
        Qt6::Qml
        Qt6::Core
)

install(TARGETS copperarch-installer
    RUNTIME DESTINATION bin
)
