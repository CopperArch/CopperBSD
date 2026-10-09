import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import CopperDashboard

Kirigami.ScrollablePage {
    id: page
    title: qsTr("Media")
    background: Rectangle { color: "transparent" }
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    readonly property var mediaApps: apps.appsInCategories(["AudioVideo", "Audio", "Video", "Player"])

    ColumnLayout {
        spacing: Theme.gap

        RowLayout {
            Layout.fillWidth: true
            Text { text: qsTr("Media"); color: Theme.text; font.pixelSize: 28; font.bold: true; Layout.fillWidth: true }
            QQC2.Button { text: qsTr("Refresh"); icon.name: "view-refresh"; onClicked: media.refresh() }
        }

        Card {
            heading: qsTr("Media stack")
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.textDim
                text: !media.installed ? qsTr("The media stack is not installed on this machine yet.")
                      : qsTr("%1 of %2 services are running. Each service runs in its own isolated jail.").arg(media.running).arg(media.total)
            }
            Repeater {
                model: media.services
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Theme.gap
                    StatusDot { ok: modelData.ok; warn: modelData.state === qsTr("Starting") }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        Text { text: modelData.label; color: Theme.text; font.pixelSize: 15; font.bold: true }
                        Text { text: modelData.role + "  ·  " + modelData.address; color: Theme.textDim; font.pixelSize: 12 }
                    }
                    Text { text: modelData.state; color: modelData.ok ? Theme.ok : Theme.textDim; font.pixelSize: 14 }
                }
            }
        }

        Card {
            heading: qsTr("Media applications")
            Text {
                visible: page.mediaApps.length === 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.textDim
                text: qsTr("No media player application is installed.")
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.gap / 2
                Repeater {
                    model: page.mediaApps
                    delegate: QQC2.Button {
                        required property var modelData
                        text: modelData.name
                        icon.name: modelData.iconName
                        onClicked: apps.launch(modelData.appId)
                    }
                }
            }
        }
    }
}
