import QtQuick
import CopperDashboard

/*! Dashboard text: Rajdhani, uppercase, 13px — the web dashboard's body style. */
Text {
    color: Theme.ink
    font.family: Theme.mono
    font.pixelSize: 13
    font.capitalization: Font.AllUppercase
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
