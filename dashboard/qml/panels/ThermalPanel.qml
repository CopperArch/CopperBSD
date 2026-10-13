import QtQuick
import QtQuick.Layouts
import CopperDashboard

Panel {
    id: root
    property var d: ({})
    readonly property var s: (d.host || {}).sensors || {}
    readonly property var temps: s.temps || []
    readonly property var fans: s.fans || []
    title: qsTr("Thermals & fans")
    emptyText: temps.length || fans.length ? "" : qsTr("no sensor data")

    Repeater {
        model: root.temps.length      // a count, so rows survive each reading
        delegate: RowLayout {
            required property int index
            readonly property var modelData: root.temps[index] || ({})
            Layout.fillWidth: true
            spacing: 8
            T { text: modelData.label || ""; color: Theme.dim; font.pixelSize: 11; Layout.maximumWidth: root.width * 0.4 }
            Bar { pct: 100 * (Number(modelData.value) || 0) / (modelData.crit || 100); warnAt: 75; failAt: 90 }
            T { text: Theme.num(modelData.value) + "°C" }
        }
    }
    Repeater {
        model: root.fans.length
        delegate: KV {
            required property int index
            readonly property var modelData: root.fans[index] || ({})
            tiny: true
            k: (modelData.label || "") + "  " + (modelData.chip || "")
            v: (modelData.rpm || 0) + " rpm"
        }
    }
}
