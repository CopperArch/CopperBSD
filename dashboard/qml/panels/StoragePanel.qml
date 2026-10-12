import QtQuick
import QtQuick.Layouts
import CopperDashboard

Panel {
    id: root
    property var d: ({})
    readonly property var fs: (d.disks || {}).filesystems || []
    readonly property int firstMember: {
        for (let i = 0; i < fs.length; ++i)
            if (fs[i].pool_member)
                return i
        return -1
    }
    title: qsTr("Storage")
    emptyText: fs.length ? "" : qsTr("no filesystem data")

    Repeater {
        model: root.fs
        delegate: ColumnLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 1
            Sub { visible: index === root.firstMember; text: qsTr("pool members") }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                T { text: modelData.mount || ""; color: Theme.dim; Layout.maximumWidth: root.width * 0.42 }
                Bar { pct: modelData.percent || 0 }
                T {
                    text: Theme.human(modelData.used) + "/" + Theme.human(modelData.size) + " · " + Theme.num(modelData.percent) + "%"
                    font.pixelSize: 11
                }
            }
            KV { tiny: true; k: Theme.human(modelData.avail) + qsTr(" free"); v: modelData.fstype || ""; valueColor: Theme.dim }
        }
    }
}
