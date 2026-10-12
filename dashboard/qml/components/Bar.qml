import QtQuick
import QtQuick.Layouts
import CopperDashboard

/*! Thin usage bar that turns amber/red past its thresholds. */
Rectangle {
    id: bar
    property real pct: 0
    property real warnAt: 80
    property real failAt: 92
    Layout.fillWidth: true
    Layout.minimumWidth: 40
    implicitHeight: 5
    radius: 3
    color: Qt.rgba(1, 1, 1, 0.07)
    Rectangle {
        height: parent.height
        radius: 3
        width: parent.width * Math.min(100, Math.max(0, bar.pct)) / 100
        color: bar.pct >= bar.failAt ? Theme.fail : bar.pct >= bar.warnAt ? Theme.warn : Theme.ok
        Behavior on width { NumberAnimation { duration: 500 } }
    }
}
