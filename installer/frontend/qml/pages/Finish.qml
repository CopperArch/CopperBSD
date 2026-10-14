import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import CopperArch

Item {
    property bool canAdvance: false
    property bool showNav: false
    readonly property var backend: StackView.view.backend
    readonly property var answers: StackView.view.answers
    readonly property string desktopName: ({ "kde": "KDE Plasma", "gnome": "GNOME",
        "xfce": "XFCE", "niri": "Niri", "mangowc": "MangoWC",
        "all": qsTr("your desktops") })[answers.desktop] || qsTr("your desktop")

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.7
        spacing: Theme.gap

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 72; height: 72; radius: 36; color: Theme.ok
            Text {
                anchors.centerIn: parent; text: "✓"
                color: "white"; font.pixelSize: 40; font.bold: true
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Installation complete")
            color: Theme.text; font.pixelSize: Theme.fontH1; font.bold: true
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: qsTr("CopperArch Media is installed. On first boot it finishes "
                       + "setting up %1 and brings your media jails online. "
                       + "Remove the install media and reboot.").arg(desktopName)
            color: Theme.textDim; font.pixelSize: Theme.fontBody
        }
        Button {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.gap
            text: qsTr("Reboot now")
            onClicked: backend.reboot()
            background: Rectangle { radius: Theme.radius; color: Theme.accent }
            contentItem: Text {
                text: parent.text; color: Theme.accentText; font.bold: true
                leftPadding: 24; rightPadding: 24
                topPadding: 10; bottomPadding: 10
            }
        }
    }
}
