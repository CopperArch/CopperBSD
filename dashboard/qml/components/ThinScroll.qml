import QtQuick
import QtQuick.Templates as Tpl
import CopperDashboard

/*! Slim scrollbar drawn by the dashboard itself, so it looks the same under
    any desktop style and never covers the text beside it. */
Tpl.ScrollBar {
    id: bar
    implicitWidth: 6
    implicitHeight: 6
    minimumSize: 0.08
    visible: size < 1.0
    contentItem: Rectangle {
        implicitWidth: 6
        implicitHeight: 6
        radius: 3
        color: Theme.tint(Theme.blue, bar.pressed ? 0.6 : bar.hovered ? 0.45 : 0.25)
    }
    background: Rectangle { radius: 3; color: Qt.rgba(1, 1, 1, 0.04) }
}
