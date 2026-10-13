import QtQuick
import QtQuick.Controls as QQC2
import CopperDashboard

/*! One button of the terminal dock's control strip (the web page's
    #termctl button): dim until hovered, solid blue when it is the current
    choice, outlined blue for the pane picker. */
QQC2.AbstractButton {
    id: btn
    property bool on: false
    property bool accent: false
    property bool current: false
    property string tip: ""
    property int align: Text.AlignHCenter
    hoverEnabled: true
    leftPadding: 8
    rightPadding: 8
    topPadding: 4
    bottomPadding: 4
    QQC2.ToolTip.visible: hovered && tip !== ""
    QQC2.ToolTip.text: tip
    QQC2.ToolTip.delay: 500
    background: Rectangle {
        radius: 6
        color: btn.on ? Theme.blue
             : btn.accent ? Theme.tint(Theme.blue, btn.hovered ? 0.2 : 0.09)
             : btn.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        border.color: btn.on ? Theme.blue : btn.accent ? Theme.tint(Theme.blue, 0.3) : "transparent"
    }
    contentItem: Text {
        text: btn.text
        color: btn.on ? Theme.bg : (btn.accent || btn.current) ? Theme.blue : btn.hovered ? Theme.ink : Theme.dim
        font.family: Theme.mono
        font.pixelSize: 12
        font.bold: btn.on || btn.accent
        horizontalAlignment: btn.align
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
}
