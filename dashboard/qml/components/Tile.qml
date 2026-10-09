import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import CopperDashboard

// A large, keyboard- and mouse-activatable navigation tile.
QQC2.AbstractButton {
    id: tile
    property string subtitle
    property string iconName

    Layout.fillWidth: true
    Layout.preferredHeight: 128
    activeFocusOnTab: true
    hoverEnabled: true
    Accessible.name: text
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    background: Rectangle {
        radius: Theme.radius
        color: tile.down ? Theme.accent
             : (tile.hovered || tile.activeFocus) ? Theme.surfaceAlt
             : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.93)
        border.color: tile.activeFocus ? Theme.accent : Theme.border
        border.width: tile.activeFocus ? 2 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    contentItem: RowLayout {
        spacing: Theme.gap
        Kirigami.Icon {
            source: tile.iconName
            Layout.preferredWidth: 56
            Layout.preferredHeight: 56
            color: Theme.accent
            isMask: false
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: tile.text
                color: Theme.text
                font.pixelSize: 20
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: tile.subtitle
                color: Theme.textDim
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }
}
