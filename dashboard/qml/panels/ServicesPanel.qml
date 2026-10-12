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
    // Three states: no VPN jail on this machine (rows hidden), a VPN jail
    // still waiting for its WireGuard config, and a configured tunnel.
    readonly property bool hasVpn: !!d.vpn && !v.error && v.installed !== false
    readonly property bool needsConfig: hasVpn && v.configured === false
    readonly property bool bad: !needsConfig && (v.healthy !== "healthy" || !v.siblings_ok)
    signal changeVpn()
    title: qsTr("Services & VPN")

    KV {
        visible: root.hasVpn
        dot: root.needsConfig ? "w" : (root.bad ? "f" : "")
        k: qsTr("VPN")
        v: root.needsConfig ? qsTr("not set up") : (root.v.provider || qsTr("not named"))
        v2: root.needsConfig ? "" : (root.v.vpn_type || "")
        stale: root.needsConfig
    }
    T {
        visible: root.needsConfig
        Layout.preferredWidth: root.bodyWidth
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        font.pixelSize: 12
        color: Theme.dim
        text: qsTr("qBittorrent, Sonarr and Radarr stay offline until the VPN has a WireGuard config. Paste the .conf file from your provider, or from your own server.")
    }
    KV { visible: root.hasVpn && !root.needsConfig; tiny: true; k: qsTr("exit"); v: root.v.ip || "?"; v2: root.v.country || "" }
    KV {
        visible: root.hasVpn && !root.needsConfig
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
            visible: !root.needsConfig
            text: qsTr("Restart tunnel")
            tip: dash.fixInfo("vpn_rotate")
            onClicked: dash.runFixes([{ id: "vpn_rotate", args: {}, label: qsTr("Restart VPN tunnel") }], qsTr("Restarting the VPN tunnel…"))
        }
        FixBtn { text: root.needsConfig ? qsTr("Add a VPN") : qsTr("Change VPN provider"); onClicked: root.changeVpn() }
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
