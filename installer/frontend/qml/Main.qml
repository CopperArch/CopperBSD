pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import CopperArch

/*!
 * CopperArch Media — graphical installer. An Anaconda/Calamares-style wizard:
 * a fixed step rail on the left, the active page on the right, Back/Next below.
 * All wizard state lives in `answers` and is handed to InstallerBackend.start()
 * on the Summary page; the backend drives bsdinstall underneath.
 */
ApplicationWindow {
    id: root
    // Kiosk: no window manager on the live medium, so size to the whole screen.
    x: 0
    y: 0
    width: Screen.width
    height: Screen.height
    flags: Qt.Window | Qt.FramelessWindowHint
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    title: qsTr("CopperArch Media — Install")
    color: Theme.window

    // Shared, mutable wizard answers (bound by the pages).
    property var answers: ({
        "keymap": "us",
        "desktop": "kde",
        "timezone": "Europe/London",
        "disk": "",
        "zfsVdev": "stripe",
        "swapGiB": 8,
        "hostname": "copperarch-media",
        "fullname": "",
        "username": "copper",
        "password": "",
        "rootPassword": "",
        "enableMediaStack": true
    })

    // `answers` is a plain JS object, so assigning into it (answers.disk = x)
    // never notifies QML and bindings like Disk's canAdvance stay stale.
    // Pages must go through here: swapping in a fresh copy fires the change.
    function setAnswer(key, value) {
        const next = Object.assign({}, answers)
        next[key] = value
        answers = next
    }

    InstallerBackend { id: installer }

    readonly property var steps: [
        { key: "welcome",  label: qsTr("Welcome"),      src: "pages/Welcome.qml" },
        { key: "locale",   label: qsTr("Time zone"),    src: "pages/Locale.qml" },
        { key: "keyboard", label: qsTr("Keyboard"),     src: "pages/Keyboard.qml" },
        { key: "desktop",  label: qsTr("Desktop"),      src: "pages/Desktop.qml" },
        { key: "disk",     label: qsTr("Destination"),  src: "pages/Disk.qml" },
        { key: "account",  label: qsTr("Your account"), src: "pages/Account.qml" },
        { key: "summary",  label: qsTr("Summary"),      src: "pages/Summary.qml" },
        { key: "install",  label: qsTr("Install"),      src: "pages/Install.qml" },
        { key: "finish",   label: qsTr("Finished"),     src: "pages/Finish.qml" }
    ]
    property int stepIndex: 0

    // The active page may veto Next (e.g. no disk chosen, passwords blank) and
    // may hide the nav entirely (install progress / finish).
    property bool canGoNext: stackView.currentItem
                             ? (stackView.currentItem.canAdvance ?? true) : true
    property bool navVisible: stackView.currentItem
                             ? (stackView.currentItem.showNav ?? true) : true

    function goNext() {
        if (stepIndex < steps.length - 1) {
            stepIndex++;
            stackView.replace(steps[stepIndex].src);
        }
    }
    function goBack() {
        if (stepIndex > 0) {
            stepIndex--;
            stackView.replace(steps[stepIndex].src);
        }
    }
    //! Pages call this to jump straight to install (from Summary) or finish.
    function goToStep(key) {
        for (let i = 0; i < steps.length; ++i) {
            if (steps[i].key === key) {
                stepIndex = i;
                stackView.replace(steps[i].src);
                return;
            }
        }
    }

    // Branded backdrop, dimmed hard so the pages on top stay readable.
    Image {
        anchors.fill: parent
        source: "../assets/background.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Rectangle { anchors.fill: parent; color: Theme.window; opacity: 0.82 }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Step rail ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Theme.sidebarW
            color: Theme.surface

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.gap
                spacing: Theme.gap

                RowLayout {
                    spacing: 10
                    Image {
                        source: "../assets/logo.png"
                        Layout.preferredHeight: 52
                        Layout.preferredWidth: 46
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: qsTr("CopperArch")
                            color: Theme.text; font.bold: true
                            font.pixelSize: Theme.fontH2
                        }
                        Text {
                            text: qsTr("Media Server")
                            color: Theme.textDim; font.pixelSize: 12
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                Repeater {
                    model: root.steps
                    delegate: RowLayout {
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        opacity: index <= root.stepIndex ? 1.0 : 0.45

                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: index < root.stepIndex ? Theme.ok
                                 : index === root.stepIndex ? Theme.accent
                                 : "transparent"
                            border.color: Theme.border
                            border.width: index > root.stepIndex ? 1 : 0
                            Text {
                                anchors.centerIn: parent
                                text: index < root.stepIndex ? "✓"
                                                             : (index + 1)
                                color: index <= root.stepIndex ? Theme.accentText
                                                               : Theme.textDim
                                font.pixelSize: 12; font.bold: true
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: index === root.stepIndex ? Theme.text
                                                            : Theme.textDim
                            font.pixelSize: Theme.fontBody
                            font.bold: index === root.stepIndex
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                Text {
                    text: qsTr("FreeBSD 15.1 · ZFS")
                    color: Theme.textDim; font.pixelSize: 11
                }
            }
        }

        // ── Page area + nav ────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            StackView {
                id: stackView
                Layout.fillWidth: true
                Layout.fillHeight: true
                initialItem: root.steps[0].src
                clip: true
                // Expose shared handles to every page without globals.
                property var backend: installer
                property var answers: root.answers
                property var wizard: root
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1; color: Theme.border
                visible: root.navVisible
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.gap
                visible: root.navVisible
                spacing: Theme.gap

                Button {
                    text: qsTr("Back")
                    enabled: root.stepIndex > 0 && !installer.installing
                    onClicked: root.goBack()
                    background: Rectangle {
                        radius: Theme.radius; color: "transparent"
                        border.color: Theme.border; border.width: 1
                    }
                    contentItem: Text {
                        text: parent.text; color: Theme.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: root.steps[root.stepIndex].key === "summary"
                          ? qsTr("Install") : qsTr("Next")
                    enabled: root.canGoNext
                    onClicked: root.goNext()
                    background: Rectangle {
                        radius: Theme.radius
                        color: parent.enabled ? Theme.accent : Theme.surfaceAlt
                    }
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? Theme.accentText : Theme.textDim
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    leftPadding: 24; rightPadding: 24
                }
            }
        }
    }
}
