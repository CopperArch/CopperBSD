import QtQuick
import CopperDashboard

Rectangle {
    property bool ok: false
    property bool warn: false
    implicitWidth: 12
    implicitHeight: 12
    radius: 6
    color: ok ? Theme.ok : (warn ? Theme.warn : Theme.danger)
}
