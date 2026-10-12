import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import CopperDashboard

/*! Modal sheet used for the repair log and the small dialogs: title, a body,
    and a footer row of buttons. */
QQC2.Popup {
    id: sheet
    property string title: ""
    property bool busy: false
    default property alias content: body.data
    property alias footer: foot.data
    property real sheetWidth: 640
    parent: QQC2.Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(sheetWidth, parent ? parent.width * 0.94 : sheetWidth)
    modal: true
    focus: true
    padding: 0
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    QQC2.Overlay.modal: Rectangle { color: Qt.rgba(4 / 255, 7 / 255, 12 / 255, 0.72) }
    background: Rectangle { color: "#0d131c"; radius: 11; border.color: Theme.edgeHi }
    contentItem: ColumnLayout {
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 15
            Layout.bottomMargin: 10
            spacing: 9
            QQC2.BusyIndicator { running: sheet.busy; visible: sheet.busy; implicitWidth: 16; implicitHeight: 16 }
            T {
                text: sheet.title
                color: Theme.dim
                font.pixelSize: 12
                font.bold: true
                font.letterSpacing: 1.2
                Layout.fillWidth: true
            }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.edge }
        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.margins: 15
            spacing: 8
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.edge }
        RowLayout {
            id: foot
            Layout.fillWidth: true
            Layout.margins: 10
            Layout.leftMargin: 15
            Layout.rightMargin: 15
            spacing: 9
        }
    }
}
