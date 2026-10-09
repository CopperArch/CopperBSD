import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import CopperDashboard

Kirigami.ScrollablePage {
    id: page
    title: qsTr("Updates")
    background: Rectangle { color: "transparent" }
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    Component.onCompleted: if (sys.updateCount < 0 && sys.updateState === qsTr("Not checked yet")) sys.checkUpdates()

    ColumnLayout {
        spacing: Theme.gap

        Text { text: qsTr("Updates"); color: Theme.text; font.pixelSize: 28; font.bold: true }

        Card {
            heading: qsTr("Software updates")
            Text {
                text: sys.updateState
                color: sys.updateCount > 0 ? Theme.warn : Theme.text
                font.pixelSize: 20
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.textDim
                text: qsTr("Checking is a read-only dry run and needs a network connection. "
                           + "Installing updates asks for your administrator password in the tool you choose below; "
                           + "the dashboard itself never runs as root.")
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.gap / 2
                QQC2.Button { text: qsTr("Check now"); icon.name: "view-refresh"; onClicked: sys.checkUpdates() }
                QQC2.Button {
                    text: qsTr("Open Software Center")
                    icon.name: "system-software-install"
                    enabled: applicationWindow().hasSoftware()
                    onClicked: applicationWindow().openSoftware()
                }
                QQC2.Button {
                    text: qsTr("Update in a terminal")
                    icon.name: "utilities-terminal"
                    onClicked: apps.runCommand("konsole", ["-e", "sh", "-c",
                        "doas pkg upgrade; echo; echo 'Press Enter to close'; read x"])
                }
            }
        }
    }
}
