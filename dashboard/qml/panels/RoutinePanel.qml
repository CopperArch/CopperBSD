import QtQuick
import QtQuick.Layouts
import CopperDashboard

Panel {
    id: root
    property var d: ({})
    readonly property var r: d.daily_routine || {}
    readonly property var c: r.counts || {}
    signal changeSchedule()
    title: qsTr("Daily routine")
    tag: r.ran_at ? String(r.ran_at).replace("T", " ").slice(0, 16) : ""
    emptyText: r.error ? String(r.error) : ""

    component Count: ColumnLayout {
        property string label
        property int value
        property color tone
        Layout.minimumWidth: 62
        spacing: 0
        T { text: label; color: Theme.faint; font.pixelSize: 10; font.letterSpacing: 0.6 }
        T { text: value; color: tone; font.pixelSize: 26; font.bold: true }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        Count { label: qsTr("OK"); value: root.c.OK || 0; tone: Theme.ok }
        Count { label: qsTr("Warn"); value: root.c.WARN || 0; tone: Theme.warn }
        Count { label: qsTr("Fail"); value: root.c.FAIL || 0; tone: Theme.fail }
        Count { label: qsTr("Skip"); value: root.c.SKIP || 0; tone: Theme.faint }
        Item { Layout.fillWidth: true }
    }
    KV { tiny: true; k: qsTr("last run"); v: (root.r.age_hours === undefined ? "?" : root.r.age_hours) + qsTr("h ago"); stale: !!root.r.stale }
    KV { tiny: true; k: qsTr("next run"); v: root.r.next_run || qsTr("03:00 daily") }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Item { Layout.fillWidth: true }
        FixBtn {
            text: qsTr("Run quick pass")
            tip: dash.fixInfo("daily_routine_quick")
            onClicked: dash.runFixes([{ id: "daily_routine_quick", args: {}, label: qsTr("Quick routine pass") }], qsTr("Running the quick routine…"))
        }
        FixBtn { text: qsTr("Change"); onClicked: root.changeSchedule() }
    }
    Sub { visible: (root.r.entries || []).length > 0; text: qsTr("findings") }
    Repeater {
        model: root.r.entries || []
        delegate: Item {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: finding.height
            Dot { y: 5; kind: modelData.kind === "FAIL" ? "f" : modelData.kind === "WARN" ? "w" : "i" }
            T {
                id: finding
                x: 15
                width: root.bodyWidth - 15
                text: String(modelData.message || "").slice(0, 150) + "  — " + (modelData.section || "")
                color: Theme.dim; font.pixelSize: 11
                wrapMode: Text.Wrap; elide: Text.ElideNone
            }
        }
    }
}
