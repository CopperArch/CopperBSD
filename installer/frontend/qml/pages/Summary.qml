import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import CopperArch

Item {
    property bool canAdvance: true
    property bool showNav: true
    readonly property var answers: StackView.view.answers

    function row(k, v) { return { "k": k, "v": v }; }
    readonly property var rows: [
        row(qsTr("Disk"),        answers.disk + qsTr(" (will be erased)")),
        row(qsTr("Layout"),      qsTr("ZFS on root (zroot), %1 GiB swap").arg(answers.swapGiB)),
        row(qsTr("Host name"),   answers.hostname),
        row(qsTr("User"),        answers.username + (answers.fullname ? " (" + answers.fullname + ")" : "")),
        row(qsTr("Time zone"),   answers.timezone),
        row(qsTr("Keyboard"),    answers.keymap),
        row(qsTr("Media stack"), answers.enableMediaStack ? qsTr("Jellyfin/Plex/*arr + VPN + dashboard")
                                                          : qsTr("Desktop only"))
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gapLg
        spacing: Theme.gap

        Text {
            text: qsTr("Ready to install")
            color: Theme.text; font.pixelSize: Theme.fontH1; font.bold: true
        }
        Text {
            text: qsTr("Review your choices. Clicking Install erases %1.").arg(answers.disk)
            color: Theme.textDim; font.pixelSize: Theme.fontBody
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.gap
            Layout.preferredHeight: col.implicitHeight + 2 * Theme.gap
            color: Theme.surface; radius: Theme.radius; border.color: Theme.border
            ColumnLayout {
                id: col
                anchors.fill: parent
                anchors.margins: Theme.gap
                spacing: 10
                Repeater {
                    model: rows
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Text {
                            Layout.preferredWidth: 160
                            text: modelData.k; color: Theme.textDim
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.v; color: Theme.text; font.bold: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
