import QtQuick
import QtQuick.Layouts
import CopperDashboard

/*! Services & VPN: names the VPN that is active, its exit and tunnel state,
    lets you swap provider (or point it at your own server), then the endpoints. */
Panel {
    id: root
    property var d: ({})
    readonly property var v: d.vpn || {}
    readonly property var services: d.services || []
    readonly property bool hasVpn: !!d.vpn && !v.error
    readonly property bool bad: v.healthy !== "healthy" || !v.siblings_ok
    signal changeVpn()
    title: qsTr("Services & VPN")

    KV {
        visible: root.hasVpn
        dot: root.bad ? "f" : ""
        k: qsTr("VPN")
        v: root.v.provider || qsTr("not named")
        v2: root.v.vpn_type || ""
    }
    KV { visible: root.hasVpn; tiny: true; k: qsTr("exit"); v: root.v.ip || "?"; v2: root.v.country || "" }
    KV {
        visible: root.hasVpn
        tiny: true
        k: qsTr("tunnel")
        v: (root.v.healthy || "?") + qsTr(" · route ") + (root.v.siblings_ok ? qsTr("bound ✓") : qsTr("BROKEN"))
        stale: !root.v.siblings_ok
    }
    Repeater {
        model: root.hasVpn ? (root.v.siblings || []).filter(x => !x.bound) : []
        delegate: KV { required property var modelData; tiny: true; keyStale: true; k: modelData.name + qsTr(" not routed via VPN jail") }
    }
    RowLayout {
        visible: root.hasVpn
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 6
        Item { Layout.fillWidth: true }
        FixBtn {
            text: qsTr("Restart tunnel")
            tip: dash.fixInfo("vpn_rotate")
            onClicked: dash.runFixes([{ id: "vpn_rotate", args: {}, label: qsTr("Restart VPN tunnel") }], qsTr("Restarting the VPN tunnel…"))
        }
        FixBtn { text: qsTr("Change VPN provider"); onClicked: root.changeVpn() }
    }

    Sub { text: qsTr("endpoints") }
    Repeater {
        model: root.services
        delegate: KV {
            required property var modelData
            dot: modelData.ok ? "" : "f"
            k: modelData.name || ""
            tiny: false
            v: (modelData.code === null || modelData.code === undefined ? qsTr("down") : modelData.code) + " · " + modelData.ms + "ms"
        }
    }
}
