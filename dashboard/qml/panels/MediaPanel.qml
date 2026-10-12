import QtQuick
import QtQuick.Layouts
import CopperDashboard

Panel {
    id: root
    property var d: ({})
    readonly property var m: d.media || {}
    readonly property var p: m.plex || null
    readonly property var j: m.jellyfin || null
    readonly property var r: m.radarr || null
    readonly property var s: m.sonarr || null
    readonly property var q: m.qbittorrent || null
    readonly property var pw: m.prowlarr || null
    readonly property bool any: !!((p && p.libraries) || j || r || s || q || pw)
    title: qsTr("Media library")
    emptyText: m.error ? String(m.error) : any ? "" : qsTr("no media data")

    Sub { visible: !!(root.p && root.p.libraries); text: "plex" + (root.p && root.p.streams ? " · " + root.p.streams + qsTr(" streaming") : ""); Layout.topMargin: 0 }
    Repeater {
        model: root.p && root.p.libraries ? root.p.libraries : []
        delegate: KV { required property var modelData; k: modelData.title || ""; v: modelData.count === null || modelData.count === undefined ? "?" : String(modelData.count) }
    }

    Sub { visible: !!root.j; text: "jellyfin" + (root.j && root.j.streams ? " · " + root.j.streams + qsTr(" streaming") : "") }
    KV { visible: !!root.j; k: qsTr("Movies"); v: root.j ? String(root.j.movies) : "" }
    KV { visible: !!root.j; k: qsTr("Series"); v: root.j ? String(root.j.series) : "" }
    KV { visible: !!root.j; k: qsTr("Episodes"); v: root.j ? String(root.j.episodes) : "" }

    Sub { visible: !!root.r; text: "radarr" }
    KV { visible: !!root.r; k: qsTr("Movies"); v: root.r ? root.r.with_file + "/" + root.r.movies : ""; v2: root.r ? Theme.human(root.r.size) : "" }
    KV { visible: !!root.r; k: qsTr("Missing"); v: root.r ? String(root.r.missing) : "" }

    Sub { visible: !!root.s; text: "sonarr" }
    KV { visible: !!root.s; k: qsTr("Series"); v: root.s ? String(root.s.series) : "" }
    KV { visible: !!root.s; k: qsTr("Episodes"); v: root.s ? root.s.episodes + "/" + root.s.episodes_total : ""; v2: root.s ? Theme.human(root.s.size) : "" }
    KV { visible: !!root.s; k: qsTr("Missing"); v: root.s ? String(root.s.missing) : "" }

    Sub { visible: !!root.q && !root.q.error; text: "qbittorrent · " + (root.q ? root.q.connection || "" : "") }
    KV { visible: !!root.q && !root.q.error; k: qsTr("Torrents"); v: root.q ? String(root.q.torrents) : ""; v2: root.q ? "(" + root.q.incomplete + qsTr(" active)") : "" }
    KV { visible: !!root.q && !root.q.error; k: qsTr("Speed"); v: root.q ? "↓ " + Theme.human(root.q.dl_speed) + "/s · ↑ " + Theme.human(root.q.up_speed) + "/s" : "" }
    Repeater {
        model: root.q && !root.q.error ? (root.q.active || []) : []
        delegate: KV {
            required property var modelData
            tiny: true
            k: modelData.name || ""
            v: modelData.progress + "% · " + Theme.human(modelData.dl) + "/s · " + modelData.seeds + "s"
        }
    }
    KV { visible: !!root.q && !!root.q.error; tiny: true; keyStale: true; k: "qbittorrent: " + (root.q && root.q.error ? String(root.q.error).slice(0, 60) : "") }

    Sub { visible: !!root.pw; text: "prowlarr" }
    KV {
        visible: !!root.pw
        k: qsTr("Indexers")
        v: root.pw ? root.pw.enabled + "/" + root.pw.indexers + qsTr(" enabled") : ""
        v2: root.pw && root.pw.failing && root.pw.failing.length ? "· " + root.pw.failing.length + qsTr(" failing") : ""
    }
}
