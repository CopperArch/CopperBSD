import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import CopperArch

Item {
    id: page
    property bool showNav: true
    // Can't continue until a target disk is chosen.
    property bool canAdvance: answers.disk !== ""
    readonly property var answers: StackView.view.answers
    readonly property var wizard: StackView.view.wizard

    // What the chosen disk can hold. Swap is capped at a quarter of the disk
    // and a small disk gets a warning (never a block: the user knows their
    // hardware). 20 GiB is a rough floor for base + desktop + media stack.
    readonly property real gib: 1024 * 1024 * 1024
    readonly property real recommendedGiB: 20
    property real selectedBytes: 0
    readonly property real diskGiB: selectedBytes / gib
    readonly property int maxSwapGiB: selectedBytes > 0 ? Math.floor(diskGiB / 4) : 128
    readonly property real systemGiB: diskGiB - answers.swapGiB
    readonly property var backend: StackView.view.backend

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gapLg
        spacing: Theme.gap

        Text {
            text: qsTr("Installation destination")
            color: Theme.text; font.pixelSize: Theme.fontH1; font.bold: true
        }
        Text {
            Layout.fillWidth: true
            text: qsTr("Choose the disk to install onto. It will be wiped and "
                       + "given a fresh ZFS pool (zroot).")
            color: Theme.textDim; font.pixelSize: Theme.fontBody
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            color: Theme.surface
            radius: Theme.radius
            border.color: Theme.border

            ListView {
                id: disks
                anchors.fill: parent
                anchors.margins: 4
                clip: true
                model: backend.disks
                delegate: ItemDelegate {
                    required property int index
                    required property string device
                    required property string descr
                    required property string sizeHuman
                    required property real bytes
                    width: ListView.view.width
                    highlighted: answers.disk === device
                    onClicked: {
                        page.selectedBytes = bytes
                        wizard.setAnswer("disk", device)
                        const cap = Math.floor(bytes / page.gib / 4)
                        if (answers.swapGiB > cap)
                            wizard.setAnswer("swapGiB", cap)
                    }
                    background: Rectangle {
                        radius: Theme.radius
                        color: parent.highlighted ? Theme.accent
                             : parent.hovered ? Theme.surfaceAlt : "transparent"
                    }
                    contentItem: RowLayout {
                        spacing: Theme.gap
                        Text {
                            text: "●"
                            color: parent.parent.highlighted ? Theme.accentText
                                                             : Theme.textDim
                        }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            Text {
                                Layout.fillWidth: true   // else the size floats mid-row
                                elide: Text.ElideRight
                                text: descr + "  (" + device + ")"
                                color: parent.parent.parent.highlighted
                                       ? Theme.accentText : Theme.text
                                font.bold: true
                            }
                        }
                        Text {
                            text: sizeHuman
                            color: parent.parent.highlighted ? Theme.accentText
                                                            : Theme.textDim
                        }
                    }
                }
                Label {
                    anchors.centerIn: parent
                    visible: disks.count === 0
                    text: qsTr("No disks detected")
                    color: Theme.textDim
                }
            }
        }

        RowLayout {
            spacing: Theme.gap
            Button {
                text: qsTr("Rescan")
                onClicked: backend.refreshDisks()
            }
            Item { Layout.fillWidth: true }
            Text { text: qsTr("Swap (GiB)"); color: Theme.text }
            SpinBox {
                from: 0; to: page.maxSwapGiB; value: answers.swapGiB
                onValueModified: wizard.setAnswer("swapGiB", value)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: sizeNote.implicitHeight + 2 * Theme.gap
            visible: answers.disk !== ""
            radius: Theme.radius
            color: page.diskGiB < page.recommendedGiB ? "#3a3322" : Theme.surface
            border.color: page.diskGiB < page.recommendedGiB ? "#d9a441" : Theme.border
            Text {
                id: sizeNote
                anchors.fill: parent
                anchors.margins: Theme.gap
                wrapMode: Text.WordWrap
                color: page.diskGiB < page.recommendedGiB ? "#f0dca8" : Theme.textDim
                text: (page.diskGiB < page.recommendedGiB
                       ? qsTr("This disk is only %1 GiB; at least %2 GiB is recommended "
                              + "for the desktop and media stack. ")
                             .arg(page.diskGiB.toFixed(1)).arg(page.recommendedGiB)
                       : "")
                      + qsTr("%1 GiB swap leaves about %2 GiB for the system.")
                            .arg(answers.swapGiB).arg(Math.max(0, page.systemGiB).toFixed(1))
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: warn.implicitHeight + 2 * Theme.gap
            visible: answers.disk !== ""
            radius: Theme.radius
            color: "#3a2a22"
            border.color: Theme.danger
            Text {
                id: warn
                anchors.fill: parent
                anchors.margins: Theme.gap
                wrapMode: Text.WordWrap
                color: "#f0c7b8"
                text: qsTr("Everything on %1 will be erased.").arg(answers.disk)
            }
        }
        Item { Layout.fillHeight: true }
    }
}
