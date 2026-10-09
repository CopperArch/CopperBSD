// CopperBSD QuickShell starter. A minimal but real top bar (clock + launcher
// button) so Niri/MangoWC sessions aren't an empty compositor. Extend freely;
// QuickShell configs are plain QML. NOTE: runtime-untested in the authoring
// sandbox (no Qt6/Wayland there) — validated structurally, runs in the builder.
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    Variants {
        model: Quickshell.screens
        PanelWindow {
            property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true }
            implicitHeight: 30
            color: "#232730"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text {
                    text: "CopperBSD"
                    color: "#c86a3a"; font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                MouseArea {
                    width: launcher.implicitWidth; height: 20
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: Quickshell.execDetached(["fuzzel"])
                    Text { id: launcher; text: "  Apps"; color: "#eef1f6" }
                }
            }

            Text {
                id: clock
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                color: "#eef1f6"
                Timer {
                    interval: 1000; running: true; repeat: true
                    triggeredOnStart: true
                    onTriggered: clock.text = new Date().toLocaleString(
                        Qt.locale(), "ddd d MMM  HH:mm")
                }
            }
        }
    }
}
