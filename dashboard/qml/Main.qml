import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import CopperDashboard

Kirigami.ApplicationWindow {
    id: root
    title: qsTr("CopperBSD Dashboard")
    width: 1180
    height: 760
    minimumWidth: 640
    minimumHeight: 480
    visible: true

    // One page at a time: this is a control centre, not a multi-column app.
    pageStack.columnView.columnResizeMode: Kirigami.ColumnView.SingleColumn
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaders.None

    Component { id: homePage;    HomePage {} }
    Component { id: appsPage;    AppsPage {} }
    Component { id: mediaPage;   MediaPage {} }
    Component { id: networkPage; NetworkPage {} }
    Component { id: systemPage;  SystemPage {} }
    Component { id: updatesPage; UpdatesPage {} }

    readonly property var settingsIds: ["systemsettings", "kde-systemsettings", "org.kde.systemsettings"]
    readonly property var terminalIds: ["org.kde.konsole", "konsole"]
    readonly property var softwareIds: ["org.kde.discover", "org.kde.discover.urlhandler"]

    function go(component) {
        pageStack.clear()
        pageStack.push(component)
    }
    // Navigation entry points for pages (ids are not visible across files).
    function goHome()    { go(homePage) }
    function goApps()    { go(appsPage) }
    function goMedia()   { go(mediaPage) }
    function goNetwork() { go(networkPage) }
    function goSystem()  { go(systemPage) }
    function goUpdates() { go(updatesPage) }
    function openSettings() { apps.launchFirst(settingsIds) }
    function openTerminal() { apps.launchFirst(terminalIds) }
    function openSoftware() { apps.launchFirst(softwareIds) }
    function hasSoftware()  { return apps.firstInstalled(softwareIds) !== "" }

    Component.onCompleted: go(homePage)

    background: Item {
        Rectangle { anchors.fill: parent; color: Theme.window }
        Image {
            anchors.fill: parent
            source: "qrc:/qt/qml/CopperDashboard/assets/background.jpg"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Rectangle { anchors.fill: parent; color: Theme.window; opacity: 0.84 }
    }

    globalDrawer: Kirigami.GlobalDrawer {
        id: drawer
        modal: false
        collapsible: true
        collapsed: root.width < 900
        width: 260
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

        header: Kirigami.AbstractApplicationHeader {
            contentItem: RowLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                Image {
                    source: "qrc:/qt/qml/CopperDashboard/assets/logo.png"
                    fillMode: Image.PreserveAspectFit
                    Layout.preferredHeight: 40
                    Layout.preferredWidth: 36
                    smooth: true
                }
                Kirigami.Heading {
                    visible: !drawer.collapsed
                    text: qsTr("CopperBSD")
                    level: 2
                    Layout.fillWidth: true
                }
            }
        }
        actions: [
            Kirigami.Action { text: qsTr("Home");     icon.name: "go-home";                    onTriggered: root.go(homePage) },
            Kirigami.Action { text: qsTr("Apps");     icon.name: "view-list-icons";            onTriggered: root.go(appsPage) },
            Kirigami.Action { text: qsTr("Media");    icon.name: "applications-multimedia";    onTriggered: root.go(mediaPage) },
            Kirigami.Action { text: qsTr("Files");    icon.name: "folder-open";                onTriggered: apps.openHome() },
            Kirigami.Action { text: qsTr("Network");  icon.name: "network-wired";              onTriggered: root.go(networkPage) },
            Kirigami.Action { text: qsTr("System");   icon.name: "computer";                   onTriggered: root.go(systemPage) },
            Kirigami.Action { text: qsTr("Updates");  icon.name: "system-software-update";     onTriggered: root.go(updatesPage) },
            Kirigami.Action { text: qsTr("Settings"); icon.name: "preferences-system";         onTriggered: root.openSettings() }
        ]
    }
}
