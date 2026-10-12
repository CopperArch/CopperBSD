import QtQuick
import QtQuick.Layouts
import CopperDashboard

/*! One "key ........ value" row. dot: "none" hides it, otherwise a Dot kind. */
RowLayout {
    id: row
    property string k: ""
    property string v: ""
    property string v2: ""          // dimmed suffix after the value
    property bool tiny: false
    property bool stale: false      // value shown in the failure colour
    property bool keyStale: false
    property string dot: "none"
    property color valueColor: Theme.ink
    Layout.fillWidth: true
    spacing: 8
    Dot { visible: row.dot !== "none"; kind: row.dot === "none" ? "" : row.dot }
    T {
        text: row.k
        color: row.keyStale ? Theme.fail : Theme.dim
        font.pixelSize: row.tiny ? 11 : 13
        Layout.fillWidth: true
    }
    T {
        text: row.v
        color: row.stale ? Theme.fail : row.valueColor
        font.pixelSize: row.tiny ? 11 : 13
        horizontalAlignment: Text.AlignRight
    }
    T {
        visible: row.v2 !== ""
        text: row.v2
        color: Theme.dim
        font.pixelSize: row.tiny ? 11 : 13
    }
}
