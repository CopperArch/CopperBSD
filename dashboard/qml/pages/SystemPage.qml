import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import CopperDashboard

Kirigami.ScrollablePage {
    id: page
    title: qsTr("System")
    background: Rectangle { color: "transparent" }
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    ColumnLayout {
        spacing: Theme.gap

        Text { text: qsTr("System"); color: Theme.text; font.pixelSize: 28; font.bold: true }

        Card {
            heading: qsTr("This machine")
            GridLayout {
                columns: 2
                columnSpacing: Theme.gapLg
                rowSpacing: 6
                Text { text: qsTr("Host name"); color: Theme.textDim }
                Text { text: sys.hostname; color: Theme.text; font.bold: true }
                Text { text: qsTr("Operating system"); color: Theme.textDim }
                Text { text: sys.osName; color: Theme.text; font.bold: true }
                Text { text: qsTr("Kernel"); color: Theme.textDim }
                Text { text: sys.kernel; color: Theme.text; Layout.fillWidth: true; elide: Text.ElideRight }
                Text { text: qsTr("Processor"); color: Theme.textDim }
                Text { text: sys.cpuModel + " (" + sys.cpuCores + " " + qsTr("cores") + ")"; color: Theme.text; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                Text { text: qsTr("Uptime"); color: Theme.textDim }
                Text { text: sys.uptime; color: Theme.text; font.bold: true }
            }
        }

        Card {
            heading: qsTr("Resources")
            Meter { label: qsTr("CPU"); valueText: Math.round(sys.cpuUsage * 100) + " %"; fraction: sys.cpuUsage }
            Meter {
                label: qsTr("Memory")
                valueText: sys.formatBytes(sys.memUsed) + " / " + sys.formatBytes(sys.memTotal)
                fraction: sys.memTotal > 0 ? sys.memUsed / sys.memTotal : 0
            }
            Meter {
                label: qsTr("Storage  ") + sys.storageName
                valueText: sys.formatBytes(sys.storageUsed) + " / " + sys.formatBytes(sys.storageTotal)
                fraction: sys.storageTotal > 0 ? sys.storageUsed / sys.storageTotal : 0
            }
        }
    }
}
