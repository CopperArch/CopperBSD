import QtQuick
import QtQuick.Layouts
import CopperDashboard

Panel {
    id: root
    property var d: ({})
    readonly property var h: d.host || {}
    readonly property var c: h.cpu || {}
    readonly property var m: h.memory || {}
    readonly property var l: h.load || {}
    title: qsTr("CPU & memory")
    emptyText: h.error ? String(h.error) : ""

    component Stat: ColumnLayout {
        property string label
        property string value
        property string unit: ""
        Layout.minimumWidth: 62
        spacing: 0
        T { text: label; color: Theme.faint; font.pixelSize: 10; font.letterSpacing: 0.6 }
        RowLayout {
            spacing: 1
            T { text: value; color: Theme.bright; font.pixelSize: 26; font.bold: true }
            T { text: unit; color: Theme.dim; font.pixelSize: 11; Layout.alignment: Qt.AlignBottom; bottomPadding: 4 }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        spacing: 14
        Stat { label: qsTr("CPU"); value: Theme.num(root.c.total); unit: "%" }
        Stat { label: qsTr("Memory"); value: Theme.num(root.m.percent); unit: "%" }
        Stat { label: qsTr("Load"); value: Theme.num(root.l["1"], 2) }
        Item { Layout.fillWidth: true }
    }
    T {
        text: String(root.c.model || "").replace(/\(R\)|\(TM\)|CPU/g, "").replace(/\s+/g, " ").trim()
        color: Theme.dim; font.pixelSize: 11; Layout.fillWidth: true
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        T { text: qsTr("RAM"); color: Theme.dim }
        Bar { pct: root.m.percent || 0 }
        T { text: Theme.human(root.m.used) + " / " + Theme.human(root.m.total); font.pixelSize: 11 }
    }
    RowLayout {
        visible: !!root.m.swap_total
        Layout.fillWidth: true
        spacing: 8
        T { text: qsTr("Swap"); color: Theme.dim }
        Bar { pct: root.m.swap_total ? 100 * root.m.swap_used / root.m.swap_total : 0; warnAt: 40; failAt: 75 }
        T { text: Theme.human(root.m.swap_used) + " / " + Theme.human(root.m.swap_total); font.pixelSize: 11 }
    }
    KV {
        tiny: true
        k: qsTr("load 1/5/15")
        v: Theme.num(root.l["1"], 2) + " · " + Theme.num(root.l["5"], 2) + " · " + Theme.num(root.l["15"], 2)
        v2: "(" + (root.l.ncpu || "?") + " cpu)"
    }
    Item {
        id: coresBox
        readonly property int n: Math.max(1, Math.floor((width + 3) / 33))
        readonly property real cell: (width - (n - 1) * 3) / n
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: cores.implicitHeight
        Grid {
            id: cores
            columns: coresBox.n
            spacing: 3
            Repeater {
                // a count, not the list: the cells stay and their bars glide
                // to each new reading instead of being rebuilt every 2 s
                model: (root.c.cores || []).length
                delegate: Rectangle {
                    required property int index
                    readonly property var modelData: (root.c.cores || [])[index]
                    width: coresBox.cell
                    height: 26
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.06)
                    clip: true
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: parent.height * Math.min(100, Number(modelData) || 0) / 100
                        color: Theme.blue; opacity: 0.75
                        Behavior on height { NumberAnimation { duration: 500 } }
                    }
                    T { anchors.centerIn: parent; text: Math.round(Number(modelData) || 0); font.pixelSize: 10; color: Theme.bright }
                }
            }
        }
    }
}
