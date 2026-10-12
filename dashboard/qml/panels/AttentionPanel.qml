import QtQuick
import QtQuick.Layouts
import CopperDashboard

/*! "Needs attention": failed / warnings / needs doing, each item with its
    one-click fix, and a "Fix all" per bucket. */
Panel {
    id: root
    property var d: ({})
    readonly property var att: d.attention || {}
    readonly property var buckets: [
        { key: "fail", title: qsTr("Failed"), what: qsTr("failing item(s)"), color: Theme.fail, items: att.failed || [] },
        { key: "warn", title: qsTr("Warnings"), what: qsTr("warning(s)"), color: Theme.warn, items: att.warning || [] },
        { key: "todo", title: qsTr("Needs doing"), what: qsTr("task(s)"), color: Theme.todo, items: att.todo || [] }
    ]
    readonly property int total: buckets[0].items.length + buckets[1].items.length + buckets[2].items.length
    title: qsTr("Needs attention")
    tag: total ? qsTr("%n item(s)", "", total) : ""
    emptyText: dash.reachable ? "" : qsTr("no status data yet")

    /*! Distinct fixes in a bucket — several findings often share one remedy. */
    function fixesOf(items) {
        const seen = {}, out = []
        for (const i of items) {
            if (!i.fix)
                continue
            const key = i.fix.id + JSON.stringify(i.fix.args || {})
            if (seen[key])
                continue
            seen[key] = true
            out.push(i.fix)
        }
        return out
    }
    /*! What the header verdict repairs: the most serious bucket with a fix. */
    readonly property var fixable: {
        for (const b of buckets) {
            const f = fixesOf(b.items)
            if (f.length)
                return { fixes: f, what: b.what }
        }
        return { fixes: [], what: "" }
    }

    Repeater {
        model: root.buckets
        delegate: ColumnLayout {
            id: bucket
            required property var modelData
            readonly property var fixes: root.fixesOf(modelData.items)
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            spacing: 5
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                T { text: bucket.modelData.title; color: bucket.modelData.color; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1 }
                Rectangle {
                    radius: 10; color: Qt.rgba(1, 1, 1, 0.09)
                    implicitWidth: n.implicitWidth + 14; implicitHeight: 16
                    T { id: n; anchors.centerIn: parent; text: bucket.modelData.items.length; font.pixelSize: 10; color: Theme.ink }
                }
                Item { Layout.fillWidth: true }
                FixBtn {
                    visible: bucket.fixes.length > 0
                    text: qsTr("Fix all %1").arg(bucket.fixes.length)
                    tip: bucket.fixes.map(f => f.label).join("\n")
                    onClicked: dash.runFixes(bucket.fixes, qsTr("Repairing %1 %2").arg(bucket.fixes.length).arg(bucket.modelData.what))
                }
            }
            T {
                visible: bucket.modelData.items.length === 0
                text: qsTr("nothing here — all clear")
                color: Theme.faint; font.italic: true; font.pixelSize: 11
                topPadding: 6; bottomPadding: 6; leftPadding: 2
            }
            Repeater {
                model: bucket.modelData.items
                delegate: Rectangle {
                    id: item
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: Math.max(txt.height, btns.height) + 12
                    radius: 7
                    color: Theme.tint(bucket.modelData.color, 0.075)
                    Rectangle { width: 3; height: parent.height; radius: 2; color: bucket.modelData.color }
                    Column {
                        id: txt
                        x: 11
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.bodyWidth - 11 - 8 - (btns.width > 0 ? btns.width + 9 : 0)
                        spacing: 1
                        T { width: parent.width; text: item.modelData.source || ""; color: Theme.faint; font.pixelSize: 10; font.letterSpacing: 0.4 }
                        T { width: parent.width; text: item.modelData.message || ""; wrapMode: Text.Wrap; elide: Text.ElideNone }
                        T {
                            width: parent.width
                            visible: !!item.modelData.action
                            text: "↳ " + (item.modelData.action || "")
                            color: Theme.blue; opacity: 0.85; font.pixelSize: 11
                            wrapMode: Text.WrapAnywhere; elide: Text.ElideNone
                        }
                    }
                    Row {
                        id: btns
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 6
                        FixBtn {
                            visible: !!item.modelData.fix
                            text: qsTr("Fix")
                            tip: item.modelData.fix ? (item.modelData.fix.label || "") : ""
                            onClicked: dash.runFixes([item.modelData.fix], item.modelData.fix.label || qsTr("Repair"))
                        }
                        FixBtn {
                            visible: !!item.modelData.open
                            text: item.modelData.open ? (item.modelData.open.label || qsTr("Open")) : ""
                            onClicked: dash.openLink(item.modelData.open.id)
                        }
                    }
                }
            }
        }
    }
}
