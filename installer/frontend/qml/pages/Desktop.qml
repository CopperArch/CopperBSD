import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import CopperArch

Item {
    property bool canAdvance: true
    property bool showNav: true
    readonly property var answers: StackView.view.answers
    readonly property var wizard: StackView.view.wizard

    // key -> what the backend's desktop_pkgs() understands
    readonly property var options: [
        { key: "kde",      name: "KDE Plasma",        blurb: qsTr("Full traditional desktop (X11 + Wayland).") },
        { key: "gnome",    name: "GNOME",             blurb: qsTr("Full GNOME desktop (Wayland).") },
        { key: "xfce",     name: "XFCE",              blurb: qsTr("Lightweight traditional desktop (X11).") },
        { key: "niri",     name: "Niri + QuickShell", blurb: qsTr("Scrollable-tiling Wayland compositor with QuickShell. Needs an AMD or Intel GPU.") },
        { key: "mangowc",  name: "MangoWC + QuickShell", blurb: qsTr("dwl/wlroots tiling Wayland compositor with QuickShell. Needs an AMD or Intel GPU.") },
        { key: "all",      name: "All of the above",  blurb: qsTr("Install every session; pick one at each login.") }
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gapLg
        spacing: Theme.gap

        Text {
            text: qsTr("Choose your desktop")
            color: Theme.text; font.pixelSize: Theme.fontH1; font.bold: true
        }
        Text {
            Layout.fillWidth: true
            text: qsTr("The login screen lets you switch between any sessions you "
                       + "install here. Wayland sessions use seatd + dbus (no systemd).")
            color: Theme.textDim; font.pixelSize: Theme.fontBody; wrapMode: Text.WordWrap
        }

        ColumnLayout {
            Layout.topMargin: Theme.gap
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: options
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    radius: Theme.radius
                    color: answers.desktop === modelData.key ? Theme.accent
                         : ma.containsMouse ? Theme.surfaceAlt : Theme.surface
                    border.color: Theme.border
                    MouseArea {
                        id: ma; anchors.fill: parent; hoverEnabled: true
                        onClicked: wizard.setAnswer("desktop", modelData.key)
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.gap
                        anchors.rightMargin: Theme.gap
                        spacing: Theme.gap
                        Rectangle {
                            Layout.preferredWidth: 18; Layout.preferredHeight: 18; radius: 9
                            color: "transparent"
                            border.width: 2
                            border.color: answers.desktop === modelData.key
                                          ? Theme.accentText : Theme.textDim
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8; height: 8; radius: 4
                                visible: answers.desktop === modelData.key
                                color: Theme.accentText
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                // fillWidth on the texts lets the column take the
                                // row's width; without it the column stays at its
                                // text width and floats, so every card's text
                                // started at a different x.
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelData.name
                                color: answers.desktop === modelData.key ? Theme.accentText : Theme.text
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelData.blurb
                                color: answers.desktop === modelData.key ? Theme.accentText : Theme.textDim
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
