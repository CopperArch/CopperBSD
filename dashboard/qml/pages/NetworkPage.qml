import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import CopperDashboard

Kirigami.ScrollablePage {
    id: page
    title: qsTr("Network")
    background: Rectangle { color: "transparent" }
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary

    ColumnLayout {
        spacing: Theme.gap

        Text { text: qsTr("Network"); color: Theme.text; font.pixelSize: 28; font.bold: true }

        Card {
            RowLayout {
                spacing: Theme.gap
                StatusDot { ok: sys.online }
                Text {
                    text: sys.online ? qsTr("Connected") : qsTr("Not connected")
                    color: Theme.text
                    font.pixelSize: 18
                    font.bold: true
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.textDim
                text: sys.online ? qsTr("This machine has an active network address.")
                                 : qsTr("No active network interface with an address was found.")
            }
        }

        Repeater {
            model: sys.interfaces
            delegate: Card {
                required property var modelData
                heading: modelData.kind + "  ·  " + modelData.name
                Layout.fillWidth: true
                GridLayout {
                    columns: 2
                    columnSpacing: Theme.gapLg
                    rowSpacing: 4
                    Text { text: qsTr("Status");   color: Theme.textDim }
                    Text { text: modelData.up ? qsTr("Up") : qsTr("Down"); color: modelData.up ? Theme.ok : Theme.danger; font.bold: true }
                    Text { text: qsTr("IPv4");     color: Theme.textDim }
                    Text { text: modelData.ipv4 !== "" ? modelData.ipv4 : qsTr("none"); color: Theme.text }
                    Text { text: qsTr("IPv6");     color: Theme.textDim; visible: modelData.ipv6 !== "" }
                    Text { text: modelData.ipv6;   color: Theme.text; visible: modelData.ipv6 !== ""; wrapMode: Text.WrapAnywhere; Layout.fillWidth: true }
                    Text { text: qsTr("Hardware address"); color: Theme.textDim }
                    Text { text: modelData.mac;    color: Theme.text }
                }
            }
        }

        Text {
            visible: sys.interfaces.length === 0
            text: qsTr("No network interfaces found.")
            color: Theme.textDim
        }
    }
}
