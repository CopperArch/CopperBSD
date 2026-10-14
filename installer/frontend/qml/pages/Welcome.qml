import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import CopperArch

Item {
    id: page
    property bool canAdvance: true
    property bool showNav: true

    // One titled card: a heading and a list of "name — what it is" bullets.
    component Card: Rectangle {
        property string heading
        property var items: []
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: col.implicitHeight + 2 * Theme.gap
        color: Theme.surface
        radius: Theme.radius
        border.color: Theme.border

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: Theme.gap
            spacing: Theme.gap / 2

            Text {
                text: heading
                color: Theme.accent
                font.pixelSize: Theme.fontBody + 2
                font.bold: true
            }
            Repeater {
                model: items
                delegate: Text {
                    required property var modelData
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.textDim
                    font.pixelSize: Theme.fontBody
                    textFormat: Text.StyledText
                    text: "<b><font color='" + Theme.text + "'>" + modelData[0]
                          + "</font></b> — " + modelData[1]
                }
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight + 2 * Theme.gapLg
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: body
            x: Theme.gapLg
            y: Theme.gapLg
            width: parent.width - 2 * Theme.gapLg
            spacing: Theme.gap

            Text {
                text: qsTr("Welcome to CopperArch Media")
                color: Theme.text
                font.pixelSize: Theme.fontH1
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                text: qsTr("A FreeBSD 15.1 media server with a desktop of your "
                           + "choice, your Jellyfin / Plex / *arr stack in jails, "
                           + "a WireGuard VPN kill-switch and a self-healing "
                           + "dashboard — all installed in a few clicks.")
                color: Theme.textDim
                font.pixelSize: Theme.fontBody
                wrapMode: Text.WordWrap
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

            GridLayout {
                Layout.fillWidth: true
                columns: width > 1100 ? 2 : 1
                columnSpacing: Theme.gap
                rowSpacing: Theme.gap

                Card {
                    heading: qsTr("What gets installed")
                    items: [
                        [qsTr("FreeBSD 15.1-RELEASE"), qsTr("the base system, on ZFS (pool “zroot”)")],
                        [qsTr("A desktop of your choice"), qsTr("KDE Plasma, GNOME, XFCE, Niri or MangoWC, with the SDDM login screen")],
                        [qsTr("Media stack"), qsTr("Jellyfin, Plex and the *arr apps, each isolated in its own jail")],
                        [qsTr("VPN kill-switch"), qsTr("WireGuard with a pf rule set that blocks traffic if the tunnel drops")],
                        [qsTr("Remote access"), qsTr("Caddy reverse proxy with automatic HTTPS and dynamic DNS")],
                        [qsTr("Dashboard"), qsTr("a web dashboard that monitors and restarts the services")]
                    ]
                }
                Card {
                    heading: qsTr("What FreeBSD gives you")
                    items: [
                        [qsTr("ZFS built in"), qsTr("snapshots, checksummed data and boot environments, so a bad update can be rolled back")],
                        [qsTr("Jails"), qsTr("lightweight, mature isolation for each service")],
                        [qsTr("pf firewall"), qsTr("one clear rule language for the whole machine")],
                        [qsTr("One coherent system"), qsTr("kernel and userland are developed together and released as a unit")],
                        [qsTr("Ports and packages"), qsTr("tens of thousands of ready-made packages through pkg")],
                        [qsTr("Permissive licence"), qsTr("the BSD licence, with long-supported stable releases")]
                    ]
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.gap
                text: qsTr("The next steps let you choose the time zone, keyboard and the "
                           + "disk to install onto, then create your account. "
                           + "Nothing is written to disk until you confirm on the "
                           + "Summary page.")
                color: Theme.textDim
                font.pixelSize: Theme.fontBody
                wrapMode: Text.WordWrap
            }
        }
    }
}
