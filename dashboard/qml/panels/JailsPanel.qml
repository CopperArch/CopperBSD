import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import CopperDashboard

/*! The jails (the Linux edition's "Containers"): one tile each, click to open
    the app, click a green dot to swap the usage for the installed version. */
Panel {
    id: root
    property var d: ({})
    readonly property var k: d.docker || {}
    readonly property var list: k.containers || []
    property var verShown: ({})
    title: qsTr("Jails")
    tag: k.error || k.total === undefined ? "" : qsTr("%1/%2 running").arg(k.running).arg(k.total)
    emptyText: k.error ? String(k.error) : list.length ? "" : qsTr("no jails found")

    Item {
        id: box
        readonly property int n: Math.max(1, Math.floor((width + 5) / 220))
        readonly property real cell: (width - (n - 1) * 5) / n
        Layout.fillWidth: true
        implicitHeight: grid.implicitHeight
        Grid {
        id: grid
        columns: box.n
        spacing: 5
        Repeater {
            model: root.list
            delegate: QQC2.AbstractButton {
                id: tile
                required property var modelData
                readonly property bool bad: modelData.state !== "running" || modelData.health === "unhealthy"
                readonly property bool warnish: modelData.health === "starting" || modelData.restarts >= 5
                readonly property bool green: !bad && !warnish
                readonly property bool shown: green && !!root.verShown[modelData.name]
                readonly property string detail: modelData.state !== "running" ? modelData.state
                    : modelData.cpu !== null && modelData.cpu !== undefined
                        ? Theme.num(modelData.cpu) + "% · " + String(modelData.mem || "").split(" / ")[0]
                        : (modelData.since || "")
                width: box.cell
                height: 27
                hoverEnabled: true
                onClicked: dash.openLink(modelData.name)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 700
                QQC2.ToolTip.text: (modelData.image || "") + " — " + (modelData.status || "") + qsTr(" · click to open")
                    + (green ? qsTr(" · click the dot for the installed version") : "")
                background: Rectangle {
                    radius: 6
                    color: tile.bad ? Theme.tint(Theme.fail, 0.1) : tile.warnish ? Theme.tint(Theme.warn, 0.09)
                         : Qt.rgba(1, 1, 1, tile.hovered ? 0.07 : 0.035)
                    border.color: tile.bad ? Theme.tint(Theme.fail, 0.35) : "transparent"
                }
                contentItem: RowLayout {
                    spacing: 7
                    Dot {
                        Layout.leftMargin: 7
                        kind: tile.bad ? "f" : tile.warnish ? "w" : ""
                        TapHandler {
                            enabled: tile.green
                            onTapped: {
                                const v = Object.assign({}, root.verShown)
                                v[tile.modelData.name] = !v[tile.modelData.name]
                                root.verShown = v
                            }
                        }
                    }
                    T { text: tile.modelData.name || ""; Layout.fillWidth: true }
                    T {
                        Layout.rightMargin: 7
                        text: tile.shown ? (tile.modelData.version || qsTr("version not reported")) : tile.detail
                        color: tile.shown ? Theme.blue : Theme.faint
                        font.pixelSize: 10
                    }
                }
            }
        }
    }
    }
}
