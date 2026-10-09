import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import CopperArch

Item {
    id: page
    property bool canAdvance: false
    property bool showNav: false          // progress page owns the flow
    readonly property var backend: StackView.view.backend
    readonly property var answers: StackView.view.answers
    readonly property var wizard: StackView.view.wizard

    Component.onCompleted: backend.start(answers)

    Connections {
        target: backend
        function onLogLine(line) {
            logModel.append({ "line": line });
            logView.positionViewAtEnd();
        }
        function onFinished(ok, message) {
            if (ok) {
                wizard.goToStep("finish");
            } else {
                errorBox.text = message;
                errorBox.visible = true;
            }
        }
    }
    ListModel { id: logModel }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gapLg
        spacing: Theme.gap

        Text {
            text: qsTr("Installing CopperArch Media")
            color: Theme.text; font.pixelSize: Theme.fontH1; font.bold: true
        }
        Text {
            text: backend.step
            color: Theme.textDim; font.pixelSize: Theme.fontBody
        }

        ProgressBar {
            Layout.fillWidth: true
            from: 0; to: 100; value: backend.progress
            background: Rectangle {
                implicitHeight: 10; radius: 5; color: Theme.surfaceAlt
            }
            contentItem: Item {
                Rectangle {
                    width: parent.width * backend.progress / 100
                    height: parent.height; radius: 5; color: Theme.accent
                }
            }
        }
        Text {
            text: backend.progress + "%"
            color: Theme.textDim; font.pixelSize: 12
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#12151a"; radius: Theme.radius; border.color: Theme.border
            ListView {
                id: logView
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                model: logModel
                delegate: Text {
                    required property string line
                    width: ListView.view.width
                    text: line
                    color: Theme.textDim
                    font.family: "monospace"
                    font.pixelSize: 12
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            id: errorBox
            property alias text: errLabel.text
            visible: false
            Layout.fillWidth: true
            Layout.preferredHeight: errLabel.implicitHeight + 2 * Theme.gap
            radius: Theme.radius; color: "#3a2020"; border.color: Theme.danger
            RowLayout {
                anchors.fill: parent; anchors.margins: Theme.gap
                spacing: Theme.gap
                Text {
                    id: errLabel; Layout.fillWidth: true
                    color: "#f0c0c0"; wrapMode: Text.WordWrap
                }
                Button {
                    text: qsTr("Back to Summary")
                    onClicked: wizard.goToStep("summary")
                }
            }
        }
    }
}
