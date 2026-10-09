import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import CopperArch

Item {
    id: page
    property bool showNav: true
    property bool canAdvance:
        hostname.text.length > 0 &&
        username.text.length > 0 &&
        pw.text.length >= 8 &&
        pw.text === pw2.text &&
        rootpw.text.length >= 8
    readonly property var answers: StackView.view.answers

    // Persist as the user types so Summary/Install see the latest values.
    function sync() {
        answers.hostname = hostname.text
        answers.fullname = fullname.text
        answers.username = username.text
        answers.password = pw.text
        answers.rootPassword = rootpw.text
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.gapLg
        spacing: Theme.gap

        Text {
            text: qsTr("Create your account")
            color: Theme.text; font.pixelSize: Theme.fontH1; font.bold: true
        }

        GridLayout {
            columns: 2; columnSpacing: Theme.gap; rowSpacing: Theme.gap
            Layout.topMargin: Theme.gap

            Text { text: qsTr("Host name"); color: Theme.text }
            TextField {
                id: hostname; Layout.preferredWidth: 340
                text: answers.hostname; onTextChanged: page.sync()
            }
            Text { text: qsTr("Full name"); color: Theme.text }
            TextField {
                id: fullname; Layout.preferredWidth: 340
                text: answers.fullname; onTextChanged: page.sync()
            }
            Text { text: qsTr("Username"); color: Theme.text }
            TextField {
                id: username; Layout.preferredWidth: 340
                text: answers.username; onTextChanged: page.sync()
            }
            Text { text: qsTr("Password"); color: Theme.text }
            TextField {
                id: pw; Layout.preferredWidth: 340
                echoMode: TextInput.Password; onTextChanged: page.sync()
            }
            Text { text: qsTr("Confirm"); color: Theme.text }
            TextField {
                id: pw2; Layout.preferredWidth: 340
                echoMode: TextInput.Password
            }
            Text { text: qsTr("Root password"); color: Theme.text }
            TextField {
                id: rootpw; Layout.preferredWidth: 340
                echoMode: TextInput.Password; onTextChanged: page.sync()
            }
        }

        Text {
            visible: pw.text.length > 0 && pw.text !== pw2.text
            text: qsTr("Passwords do not match")
            color: Theme.danger; font.pixelSize: 12
        }
        Text {
            visible: (pw.text.length > 0 && pw.text.length < 8)
                     || (rootpw.text.length > 0 && rootpw.text.length < 8)
            text: qsTr("Passwords must be at least 8 characters")
            color: Theme.danger; font.pixelSize: 12
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontBody
            // Tell the user why Next is greyed out instead of leaving them guessing.
            color: page.canAdvance ? Theme.textDim : "#f0c7b8"
            text: page.canAdvance
                  ? qsTr("Looks good. Click Next to review your choices.")
                  : qsTr("Next unlocks once the host name and username are filled in, "
                         + "both passwords are at least 8 characters, and the "
                         + "password and its confirmation match.")
        }
        Item { Layout.fillHeight: true }
    }
}
