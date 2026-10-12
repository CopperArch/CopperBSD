import QtQuick
import CopperDashboard

/*! Status dot. kind: "" ok (green), "w" warning, "f" failing, "i" idle. */
Rectangle {
    property string kind: ""
    implicitWidth: 7
    implicitHeight: 7
    radius: 3.5
    color: kind === "f" ? Theme.fail : kind === "w" ? Theme.warn : kind === "i" ? Theme.faint : Theme.ok
}
