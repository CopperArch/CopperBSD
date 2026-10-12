import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import CopperDashboard

Kirigami.ApplicationWindow {
    id: root
    title: qsTr("CopperBSD Dashboard")
    width: 1500
    height: 900
    minimumWidth: 640
    minimumHeight: 480
    visible: true

    // One page at a time: the dashboard, or one of the pages under "More".
    pageStack.columnView.columnResizeMode: Kirigami.ColumnView.SingleColumn
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None

    // The web dashboard's two typefaces, bundled so every edition looks alike.
    FontLoader { source: "qrc:/qt/qml/CopperDashboard/assets/fonts/Rajdhani-Regular.ttf" }
    FontLoader { source: "qrc:/qt/qml/CopperDashboard/assets/fonts/Rajdhani-Bold.ttf" }
    FontLoader { source: "qrc:/qt/qml/CopperDashboard/assets/fonts/Orbitron.ttf" }

    Component { id: dashboardPage; DashboardPage {} }
    Component { id: appsPage;    AppsPage {} }
    Component { id: mediaPage;   MediaPage {} }
    Component { id: networkPage; NetworkPage {} }
    Component { id: systemPage;  SystemPage {} }
    Component { id: updatesPage; UpdatesPage {} }

    readonly property var settingsIds: ["systemsettings", "kde-systemsettings", "org.kde.systemsettings"]
    readonly property var terminalIds: ["org.kde.konsole", "konsole"]
    readonly property var softwareIds: ["org.kde.discover", "org.kde.discover.urlhandler"]
    property bool onDashboard: true

    function go(component) {
        onDashboard = component === dashboardPage
        pageStack.clear()
        pageStack.push(component)
    }
    // Navigation entry points for pages (ids are not visible across files).
    function goHome()    { go(dashboardPage) }
    function goApps()    { go(appsPage) }
    function goMedia()   { go(mediaPage) }
    function goNetwork() { go(networkPage) }
    function goSystem()  { go(systemPage) }
    function goUpdates() { go(updatesPage) }
    function openSettings() { apps.launchFirst(settingsIds) }
    function openTerminal() { apps.launchFirst(terminalIds) }
    function openSoftware() { apps.launchFirst(softwareIds) }
    function hasSoftware()  { return apps.firstInstalled(softwareIds) !== "" }

    Component.onCompleted: {
        go(dashboardPage)
        // Fills the screen like the web dashboard does; --windowed keeps the default size.
        if (!Qt.application.arguments.includes("--windowed"))
            showMaximized()
    }

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0; color: "#111b2b" }
            GradientStop { position: 0.45; color: Theme.bg }
            GradientStop { position: 1; color: "#0c141d" }
        }
        // Faint badge behind everything, as on the web dashboard.
        Image {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.48, 620)
            height: width
            source: "qrc:/qt/qml/CopperDashboard/assets/logo.png"
            fillMode: Image.PreserveAspectFit
            opacity: 0.045
            smooth: true
        }
    }

    // Only the pages under "More" get this bar; the dashboard has its own header.
    header: Rectangle {
        visible: !root.onDashboard
        height: visible ? 44 : 0
        color: Theme.panel
        RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            spacing: 12
            FixBtn { text: qsTr("← Dashboard"); onClicked: root.goHome() }
            Text {
                text: root.pageStack.currentItem ? root.pageStack.currentItem.title : ""
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: 13; font.bold: true
                font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2
                Layout.fillWidth: true
            }
        }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.edge }
    }
}
