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
            text: qsTr("Keyboard layout")
            color: Theme.text; font.pixelSize: Theme.fontH1; font.bold: true
        }
        GridLayout {
            columns: 2; columnSpacing: Theme.gap; rowSpacing: Theme.gap
            Layout.topMargin: Theme.gap
            Text { text: qsTr("Layout"); color: Theme.text }
            ComboBox {
                Layout.preferredWidth: 360
                model: backend.keymaps
                currentIndex: Math.max(0, backend.keymaps.indexOf(answers.keymap))
                onActivated: {
                    wizard.setAnswer("keymap", currentText)
                    backend.applyKeymap(currentText)
                }
            }
        }
        TextField {
            Layout.topMargin: Theme.gap
            Layout.preferredWidth: 360
            placeholderText: qsTr("Type here to test your layout")
        }
        Item { Layout.fillHeight: true }
    }
}
