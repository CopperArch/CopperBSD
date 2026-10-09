import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import CopperDashboard

Kirigami.Page {
    id: page
    title: qsTr("Apps")
    background: Rectangle { color: "transparent" }
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Complementary
    Component.onDestruction: apps.filter = ""

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.gap

        Text { text: qsTr("Applications"); color: Theme.text; font.pixelSize: 28; font.bold: true }

        QQC2.TextField {
            id: search
            Layout.fillWidth: true
            placeholderText: qsTr("Search applications…")
            onTextChanged: apps.filter = text
            Accessible.name: qsTr("Search applications")
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: apps
            cellWidth: Math.max(150, Math.floor(width / Math.max(1, Math.floor(width / 190))))
            cellHeight: 120
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

            delegate: QQC2.AbstractButton {
                required property string appId
                required property string name
                required property string iconName
                required property string comment
                width: grid.cellWidth - 8
                height: grid.cellHeight - 8
                hoverEnabled: true
                activeFocusOnTab: true
                Keys.onReturnPressed: clicked()
                onClicked: apps.launch(appId)
                QQC2.ToolTip.visible: hovered && comment !== ""
                QQC2.ToolTip.text: comment
                QQC2.ToolTip.delay: 600
                background: Rectangle {
                    radius: Theme.radius
                    color: parent.down ? Theme.accent : (parent.hovered || parent.activeFocus ? Theme.surfaceAlt : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.93))
                    border.color: parent.activeFocus ? Theme.accent : Theme.border
                }
                contentItem: ColumnLayout {
                    spacing: 6
                    Kirigami.Icon {
                        source: iconName !== "" ? iconName : "application-x-executable"
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                    }
                    Text {
                        text: name
                        color: Theme.text
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: grid.count === 0
                text: qsTr("No applications match.")
                color: Theme.textDim
            }
        }
    }
}
