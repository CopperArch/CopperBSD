import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import CopperDashboard

Kirigami.ScrollablePage {
    id: page
    title: qsTr("Home")
    background: Rectangle { color: "transparent" }
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    readonly property int cols: Math.max(1, Math.min(3, Math.floor(width / 300)))

    ColumnLayout {
        spacing: Theme.gap

        RowLayout {
            spacing: Theme.gap
            Layout.fillWidth: true
            Image {
                source: "qrc:/qt/qml/CopperDashboard/assets/logo.png"
                fillMode: Image.PreserveAspectFit
                Layout.preferredHeight: 96
                Layout.preferredWidth: 84
                smooth: true
            }
            ColumnLayout {
                spacing: 2
                Text { text: qsTr("CopperBSD"); color: Theme.text; font.pixelSize: 34; font.bold: true }
                Text {
                    text: sys.hostname + "  ·  " + sys.osName
                    color: Theme.textDim
                    font.pixelSize: 15
                }
            }
            Item { Layout.fillWidth: true }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: page.cols
            columnSpacing: Theme.gap
            rowSpacing: Theme.gap

            Tile {
                text: qsTr("Apps"); iconName: "view-list-icons"
                subtitle: qsTr("%1 installed applications").arg(apps.totalCount)
                onClicked: applicationWindow().goApps()
            }
            Tile {
                text: qsTr("Media"); iconName: "applications-multimedia"
                subtitle: media.installed ? qsTr("%1 of %2 services running").arg(media.running).arg(media.total)
                                          : qsTr("Media stack not installed")
                onClicked: applicationWindow().goMedia()
            }
            Tile {
                text: qsTr("Files"); iconName: "folder-open"
                subtitle: qsTr("Open your home folder")
                onClicked: apps.openHome()
            }
            Tile {
                text: qsTr("Network"); iconName: "network-wired"
                subtitle: sys.online ? qsTr("Connected") : qsTr("Not connected")
                onClicked: applicationWindow().goNetwork()
            }
            Tile {
                text: qsTr("System"); iconName: "computer"
                subtitle: qsTr("Up %1").arg(sys.uptime)
                onClicked: applicationWindow().goSystem()
            }
            Tile {
                text: qsTr("Updates"); iconName: "system-software-update"
                subtitle: sys.updateState
                onClicked: applicationWindow().goUpdates()
            }
            Tile {
                text: qsTr("Terminal"); iconName: "utilities-terminal"
                subtitle: qsTr("Open a shell")
                onClicked: applicationWindow().openTerminal()
            }
            Tile {
                text: qsTr("Settings"); iconName: "preferences-system"
                subtitle: qsTr("KDE system settings")
                onClicked: applicationWindow().openSettings()
            }
        }

        Card {
            heading: qsTr("System status")
            GridLayout {
                Layout.fillWidth: true
                columns: page.width > 760 ? 3 : 1
                columnSpacing: Theme.gapLg
                rowSpacing: Theme.gap
                Meter {
                    label: qsTr("CPU")
                    valueText: Math.round(sys.cpuUsage * 100) + " %"
                    fraction: sys.cpuUsage
                }
                Meter {
                    label: qsTr("Memory")
                    valueText: sys.formatBytes(sys.memUsed) + " / " + sys.formatBytes(sys.memTotal)
                    fraction: sys.memTotal > 0 ? sys.memUsed / sys.memTotal : 0
                }
                Meter {
                    label: qsTr("Storage")
                    valueText: sys.formatBytes(sys.storageUsed) + " / " + sys.formatBytes(sys.storageTotal)
                    fraction: sys.storageTotal > 0 ? sys.storageUsed / sys.storageTotal : 0
                }
            }
        }
    }
}
