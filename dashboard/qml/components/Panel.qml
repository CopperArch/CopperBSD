import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import CopperDashboard

/*! A dashboard panel: title bar with an optional right-hand tag, and a body
    that scrolls when its rows don't fit. Children go into the body column. */
Rectangle {
    id: panel
    property string title: ""
    property string tag: ""
    property string emptyText: ""           // shown instead of the body when set
    default property alias content: body.data
    /*! Width available to a row in the body. Wrapping text sizes itself from
        this (not from the width a layout hands it), so its height is settled
        before the layout runs instead of changing underneath it. */
    readonly property real bodyWidth: Math.max(40, flick.width - 10)
    color: Theme.panel
    radius: 10
    border.color: hover.hovered ? Theme.edgeHi : Theme.edge
    clip: true
    HoverHandler { id: hover }

    Item {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 32
        T {
            anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
            text: panel.title
            color: Theme.dim
            font.pixelSize: 12
            font.bold: true
            font.letterSpacing: 1.3
        }
        T {
            anchors { right: parent.right; rightMargin: 13; verticalCenter: parent.verticalCenter }
            text: panel.tag
            color: Theme.faint
            font.pixelSize: 11
            font.capitalization: Font.MixedCase
        }
        Rectangle {     // the title underline fades from the accent to nothing
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.tint(Theme.blue, 0.45) }
                GradientStop { position: 0.6; color: Theme.edge }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom
                  leftMargin: 13; rightMargin: 13; topMargin: 9; bottomMargin: 9 }
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        QQC2.ScrollBar.vertical: ThinScroll {}
        ColumnLayout {
            id: body
            // 10px always kept clear on the right for the scrollbar: sizing the
            // body by whether it overflows would make the layout chase itself.
            width: flick.width - 10
            spacing: 5
            visible: panel.emptyText === ""
        }
        T {
            visible: panel.emptyText !== ""
            text: panel.emptyText
            color: Theme.faint
            font.italic: true
            width: flick.width
            wrapMode: Text.WordWrap
            topPadding: 10
        }
    }
}
