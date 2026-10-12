import QtQuick
import QtQuick.Controls as QQC2
import CopperDashboard

/*! The dashboard's small outlined action button (the web page's .fixbtn).
    tone: "" blue, "danger" red, "go" green. */
QQC2.AbstractButton {
    id: btn
    property string tone: ""
    property string tip: ""
    readonly property color hue: tone === "danger" ? Theme.fail : tone === "go" ? Theme.ok : Theme.blue
    hoverEnabled: true
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.45
    leftPadding: 10
    rightPadding: 10
    topPadding: 5
    bottomPadding: 5
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    QQC2.ToolTip.visible: hovered && tip !== ""
    QQC2.ToolTip.text: tip
    QQC2.ToolTip.delay: 500
    background: Rectangle {
        radius: 7
        color: Theme.tint(btn.hue, btn.down ? 0.34 : btn.hovered ? 0.24 : 0.12)
        border.color: Theme.tint(btn.hue, btn.activeFocus ? 0.9 : 0.42)
    }
    contentItem: Text {
        text: btn.text
        color: btn.hue
        font.family: Theme.mono
        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 0.4
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
