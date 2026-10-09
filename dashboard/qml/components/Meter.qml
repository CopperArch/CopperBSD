import QtQuick
import QtQuick.Layouts
import CopperDashboard

// Label + value text over a horizontal bar. `fraction` is 0..1.
ColumnLayout {
    id: meter
    property string label
    property string valueText
    property real fraction: 0

    Layout.fillWidth: true
    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        Text { text: meter.label; color: Theme.textDim; font.pixelSize: 13; Layout.fillWidth: true }
        Text { text: meter.valueText; color: Theme.text; font.pixelSize: 13; font.bold: true }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 8
        radius: 4
        color: Theme.surfaceAlt
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, meter.fraction))
            height: parent.height
            radius: 4
            color: meter.fraction > 0.9 ? Theme.danger : (meter.fraction > 0.75 ? Theme.warn : Theme.accent)
            Behavior on width { NumberAnimation { duration: 250 } }
        }
    }
}
