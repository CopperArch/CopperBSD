import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import CopperArch

Item {
    property bool canAdvance: true
    property bool showNav: true
    readonly property var answers: StackView.view.answers
    readonly property var wizard: StackView.view.wizard
    readonly property var backend: StackView.view.backend

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gapLg
        spacing: Theme.gap

        Text {
            text: qsTr("Language & time zone")
            color: Theme.text; font.pixelSize: Theme.fontH1; font.bold: true
        }
        Text {
            text: qsTr("Pick the time zone for the server's clock and logs.")
            color: Theme.textDim; font.pixelSize: Theme.fontBody
        }

        GridLayout {
            columns: 2
            columnSpacing: Theme.gap
            rowSpacing: Theme.gap
            Layout.topMargin: Theme.gap

            Text { text: qsTr("Time zone"); color: Theme.text }
            ComboBox {
                id: tz
                Layout.preferredWidth: 360
                model: backend.timezones
                currentIndex: Math.max(0, backend.timezones.indexOf(answers.timezone))
                onActivated: wizard.setAnswer("timezone", currentText)
            }
        }
        Item { Layout.fillHeight: true }
    }
}
