import QtQuick
import QtQuick.Layouts
import CopperDashboard

// A dark rounded panel with an optional heading.
Rectangle {
    id: card
    property string heading
    default property alias content: body.data

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 2 * Theme.gap
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.93)
    radius: Theme.radius
    border.color: Theme.border

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.gap
        spacing: Theme.gap / 2

        Text {
            visible: card.heading !== ""
            text: card.heading
            color: Theme.accent
            font.pixelSize: 15
            font.bold: true
        }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: Theme.gap / 2
        }
    }
}
