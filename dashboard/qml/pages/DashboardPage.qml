import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import CopperDashboard

/*! The dashboard: same header, panels and one-click repairs as the CopperArch
    Linux/FreeBSD web dashboard, drawn natively. Data and repairs come from
    the status collector + repair server through the `dash` backend. */
Kirigami.Page {
    id: page
    title: qsTr("Dashboard")
    padding: 0
    globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None
    background: Item {}

    readonly property var d: dash.status
    readonly property var host: d.host || ({})
    // d with the 2-second host gauges; for the panels that draw them
    readonly property var live: dash.liveStatus
    readonly property var liveHost: live.host || ({})
    // 4 columns on a desktop, 2 when squeezed, 1 in a narrow window — the
    // same three arrangements the web dashboard switches between.
    // Counted on the width left beside the terminal dock, at the width the
    // dock is heading for, so the panels re-arrange once and not per frame.
    readonly property real avail: width * (100 - dock.w) / 100
    readonly property int cols: avail >= 1250 ? 4 : avail >= 700 ? 2 : 1
    property real now: Date.now() / 1000
    Timer { interval: 5000; running: true; repeat: true; onTriggered: page.now = Date.now() / 1000 }

    // ── verdict ──────────────────────────────────────────────────────────
    readonly property var att: d.attention || ({})
    readonly property int nFail: (att.failed || []).length
    readonly property int nWarn: (att.warning || []).length
    readonly property int nTodo: (att.todo || []).length
    readonly property string verdictText: !dash.reachable ? qsTr("NO STATUS DATA")
        : nFail ? qsTr("%1 FAILING").arg(nFail) : nWarn ? qsTr("%1 WARNING").arg(nWarn)
        : nTodo ? qsTr("%1 TO DO").arg(nTodo) : qsTr("ALL SYSTEMS OK")
    readonly property color verdictColor: !dash.reachable ? Theme.dim : nFail ? Theme.fail : (nWarn || nTodo) ? Theme.warn : Theme.ok
    readonly property bool verdictFixable: dash.reachable && (nFail + nWarn + nTodo) > 0 && attention.fixable.fixes.length > 0

    // Dashboard and terminal sit side by side; only the dock's width changes.
    Item {
        id: main
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: page.width - dock.taken
        visible: width > 1
        clip: true
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        anchors.topMargin: 14
        anchors.bottomMargin: 12
        spacing: 10

        // ── header ───────────────────────────────────────────────────────
        // Brand on the left, verdict + actions on the right; in a narrow
        // window the actions drop to a second line instead of being cut off.
        GridLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            columns: page.cols === 1 ? 1 : 2
            columnSpacing: 12
            rowSpacing: 8
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            clip: true
            spacing: 12
            QQC2.AbstractButton {
                id: brand
                onClicked: aboutSheet.open()
                hoverEnabled: true
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: qsTr("About this system")
                QQC2.ToolTip.delay: 600
                contentItem: RowLayout {
                    spacing: 7
                    Image {
                        source: "qrc:/qt/qml/CopperDashboard/assets/logo.png"
                        fillMode: Image.PreserveAspectFit
                        Layout.preferredHeight: 32
                        Layout.preferredWidth: 30
                        smooth: true
                    }
                    Text { text: "COPPER"; color: Theme.copper; font.family: Theme.brandFont; font.pixelSize: 20; font.weight: Font.ExtraBold; font.letterSpacing: 1.5 }
                    Text { text: "BSD"; color: Theme.brandGray; font.family: Theme.brandFont; font.pixelSize: 20; font.weight: Font.ExtraBold; font.letterSpacing: 1.5 }
                    Text { visible: page.avail >= 900; text: "MEDIA SERVER"; color: Theme.blue; font.family: Theme.brandFont; font.pixelSize: 20; font.weight: Font.ExtraBold; font.letterSpacing: 1.5 }
                }
            }
            T {
                visible: page.avail >= 1100
                text: (page.host.hostname || sys.hostname) + "  " + (page.host.os || (sys.osName + " " + sys.kernel))
                color: Theme.dim; font.pixelSize: 12
                Layout.maximumWidth: 420
            }
            T {
                visible: page.avail >= 1100
                text: page.liveHost.uptime_seconds !== undefined ? qsTr("up ") + Theme.dur(page.liveHost.uptime_seconds) : qsTr("up ") + sys.uptime
                color: Theme.dim; font.pixelSize: 12
            }
            Item { Layout.fillWidth: true }
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 12
            T {
                readonly property real age: page.now - dash.generatedEpoch
                visible: page.cols === 4
                text: !dash.reachable ? qsTr("collector unreachable")
                    : age > 300 ? qsTr("data %1 — collector may be stopped").arg(age < 90 ? Math.round(age) + "s ago" : Math.round(age / 60) + "m ago")
                    : qsTr("updated %1").arg(age < 90 ? Math.max(0, Math.round(age)) + "s ago" : Math.round(age / 60) + "m ago")
                color: !dash.reachable || age > 300 ? Theme.fail : Theme.dim
                font.pixelSize: 12
            }
            QQC2.AbstractButton {
                id: verdict
                enabled: page.verdictFixable
                hoverEnabled: true
                implicitWidth: 215
                implicitHeight: 26
                onClicked: dash.runFixes(attention.fixable.fixes,
                                         qsTr("Repairing %1 %2").arg(attention.fixable.fixes.length).arg(attention.fixable.what))
                QQC2.ToolTip.visible: hovered && enabled
                QQC2.ToolTip.text: attention.fixable.fixes.map(f => f.label).join("\n")
                background: Rectangle {
                    radius: 13
                    color: Theme.tint(page.verdictColor, verdict.hovered && verdict.enabled ? 0.26 : 0.14)
                    border.color: Theme.tint(page.verdictColor, 0.42)
                }
                contentItem: Text {
                    text: page.verdictText + (page.verdictFixable ? qsTr(" — CLICK TO FIX") : "")
                    color: page.verdictColor
                    font.family: Theme.mono; font.pixelSize: 12; font.bold: true; font.letterSpacing: 0.4
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
            FixBtn {
                visible: dash.jobActive && !jobSheet.opened
                text: dash.jobRunning ? qsTr("⟳ Repair running") : dash.jobOk ? qsTr("✓ Repair done – view") : qsTr("⚠ Repair finished – view")
                onClicked: jobSheet.open()
            }
            FixBtn { text: dash.refreshing ? qsTr("⟳ Refreshing…") : qsTr("⟳ Refresh"); enabled: !dash.refreshing; tip: qsTr("Re-collect the status now"); onClicked: dash.refresh() }
            FixBtn {
                text: dash.update.available === "yes" ? qsTr("↑ Update available") : qsTr("↑ Update")
                tone: dash.update.available === "yes" ? "go" : ""
                tip: qsTr("Update CopperBSD to the latest version on GitHub, or upgrade packages")
                onClicked: { dash.checkUpdate(); updateSheet.open() }
            }
            FixBtn { text: qsTr("Reboot"); tone: "danger"; tip: qsTr("Reboot this machine"); onClicked: { rebootSheet.armed = false; rebootSheet.note = ""; rebootSheet.open() } }
            FixBtn { text: qsTr("☰ More"); onClicked: moreMenu.popup() }
        }
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(120 / 255, 160 / 255, 220 / 255, 0.1) }

        // ── no backend ───────────────────────────────────────────────────
        Rectangle {
            visible: !dash.reachable
            Layout.fillWidth: true
            implicitHeight: msg.implicitHeight + 18
            radius: 8
            color: Theme.tint(Theme.warn, 0.08)
            border.color: Theme.tint(Theme.warn, 0.35)
            T {
                id: msg
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                wrapMode: Text.Wrap; elide: Text.ElideNone
                font.capitalization: Font.MixedCase
                color: Theme.ink
                text: qsTr("The status service is not answering (%1). The panels fill in once the media stack's collector and repair server are running — they are installed with the media server. Apps, System and Network under “More” work without it.").arg(dash.error)
            }
        }

        // ── panels ───────────────────────────────────────────────────────
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: page.cols === 4 ? height : grid.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: ThinScroll {}

            GridLayout {
                id: grid
                width: flick.width - (page.cols === 4 ? 0 : 12)
                height: page.cols === 4 ? flick.height : implicitHeight
                columns: page.cols
                columnSpacing: 12
                rowSpacing: 12

                readonly property int minH: 250

                AttentionPanel {
                    id: attention
                    d: page.d
                    Layout.column: 0; Layout.row: 0
                    Layout.columnSpan: page.cols === 4 ? 2 : page.cols
                    Layout.rowSpan: page.cols === 4 ? 2 : 1
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: page.cols === 4 ? 100 : 300
                    Layout.minimumHeight: page.cols === 4 ? 120 : 260
                }
                HostPanel {
                    d: page.live
                    Layout.column: page.cols === 4 ? 2 : 0
                    Layout.row: page.cols === 4 ? 0 : 1
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: page.cols === 4 ? 100 : grid.minH
                    Layout.verticalStretchFactor: 100
                }
                ThermalPanel {
                    d: page.live
                    Layout.column: page.cols === 4 ? 3 : page.cols === 2 ? 1 : 0
                    Layout.row: page.cols === 4 ? 0 : page.cols === 2 ? 1 : 2
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: page.cols === 4 ? 100 : grid.minH
                    Layout.verticalStretchFactor: 100
                }
                JailsPanel {
                    d: page.d
                    Layout.column: page.cols === 4 ? 2 : 0
                    Layout.row: page.cols === 4 ? 1 : page.cols === 2 ? 2 : 3
                    Layout.columnSpan: page.cols === 1 ? 1 : 2
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: page.cols === 4 ? 90 : grid.minH
                    Layout.verticalStretchFactor: 90
                }
                StoragePanel {
                    d: page.live
                    Layout.column: 0
                    Layout.row: page.cols === 4 ? 2 : page.cols === 2 ? 3 : 4
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: page.cols === 4 ? 135 : 320
                    Layout.verticalStretchFactor: 135
                }
                MediaPanel {
                    d: page.d
                    Layout.column: page.cols === 1 ? 0 : 1
                    Layout.row: page.cols === 4 ? 2 : page.cols === 2 ? 3 : 5
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: page.cols === 4 ? 135 : 320
                    Layout.verticalStretchFactor: 135
                }
                ServicesPanel {
                    d: page.d
                    onChangeVpn: { vpnSheet.note = ""; vpnSheet.open() }
                    Layout.column: page.cols === 4 ? 2 : 0
                    Layout.row: page.cols === 4 ? 2 : page.cols === 2 ? 4 : 6
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: page.cols === 4 ? 135 : 320
                    Layout.verticalStretchFactor: 135
                }
                RoutinePanel {
                    d: page.d
                    onChangeSchedule: {
                        const sch = (page.d.daily_routine || {}).schedule || { frequency: "daily", time: "03:00" }
                        schedSheet.frequency = sch.frequency || "daily"
                        schedTime.text = sch.time || "03:00"
                        schedSheet.note = ""
                        schedSheet.open()
                    }
                    Layout.column: page.cols === 4 ? 3 : page.cols === 2 ? 1 : 0
                    Layout.row: page.cols === 4 ? 2 : page.cols === 2 ? 4 : 7
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: page.cols === 4 ? 135 : 320
                    Layout.verticalStretchFactor: 135
                }
            }
        }
    }

    }

    TermDock { id: dock; anchors.fill: parent }

    // ── "More": the launcher and the local system pages ──────────────────
    QQC2.Menu {
        id: moreMenu
        QQC2.MenuItem { text: qsTr("Apps"); icon.name: "view-list-icons"; onTriggered: applicationWindow().goApps() }
        QQC2.MenuItem { text: qsTr("Media apps"); icon.name: "applications-multimedia"; onTriggered: applicationWindow().goMedia() }
        QQC2.MenuItem { text: qsTr("Files"); icon.name: "folder-open"; onTriggered: apps.openHome() }
        QQC2.MenuSeparator {}
        QQC2.MenuItem { text: qsTr("Network"); icon.name: "network-wired"; onTriggered: applicationWindow().goNetwork() }
        QQC2.MenuItem { text: qsTr("System"); icon.name: "computer"; onTriggered: applicationWindow().goSystem() }
        QQC2.MenuItem { text: qsTr("Software updates"); icon.name: "system-software-update"; onTriggered: applicationWindow().goUpdates() }
        QQC2.MenuItem { text: qsTr("Terminal"); icon.name: "utilities-terminal"; onTriggered: applicationWindow().openTerminal() }
        QQC2.MenuItem { text: qsTr("Settings"); icon.name: "preferences-system"; onTriggered: applicationWindow().openSettings() }
    }

    // ── repair log ───────────────────────────────────────────────────────
    Connections {
        target: dash
        function onJobChanged() { if (dash.jobRunning && !jobSheet.opened && !jobSheet.hiddenByUser) jobSheet.open() }
        function onVpnConfigResult(ok, message) { vpnSheet.saving = false; vpnSheet.note = message; vpnSheet.noteOk = ok; if (ok) { vpnText.text = ""; vpnName.text = ""; vpnClose.start() } }
        function onScheduleResult(ok, message) { schedSheet.saving = false; schedSheet.note = message; schedSheet.noteOk = ok; if (ok) schedClose.start() }
        function onRebootResult(ok, message) { rebootSheet.note = message }
    }
    Timer { id: vpnClose; interval: 1200; onTriggered: vpnSheet.close() }
    Timer { id: schedClose; interval: 900; onTriggered: schedSheet.close() }

    Sheet {
        id: jobSheet
        property bool hiddenByUser: false
        property bool cancelArmed: false
        title: dash.jobTitle
        busy: dash.jobRunning
        sheetWidth: 980
        onOpened: { hiddenByUser = false; cancelArmed = false }
        onClosed: { if (dash.jobRunning) hiddenByUser = true; else { hiddenByUser = false; dash.dismissJob() } }
        Timer { id: disarm; interval: 4000; onTriggered: jobSheet.cancelArmed = false }

        Flickable {
            id: logFlick
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(rows.implicitHeight, page.height * 0.6)
            contentWidth: width
            contentHeight: rows.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: ThinScroll {}
            ColumnLayout {
                id: rows
                width: logFlick.width - 10
                spacing: 8
                Repeater {
                    model: dash.jobRows
                    delegate: Rectangle {
                        id: res
                        required property var modelData
                        readonly property color tone: modelData.state === "ok" ? Theme.ok : modelData.state === "bad" ? Theme.fail
                            : modelData.state === "cancelled" ? Theme.warn : modelData.state === "cur" ? Theme.blue : Theme.faint
                        Layout.fillWidth: true
                        implicitHeight: col.implicitHeight + 14
                        radius: 7
                        opacity: modelData.state === "queued" ? 0.4 : 1
                        color: modelData.state === "cur" ? Theme.tint(Theme.blue, 0.06) : Qt.rgba(1, 1, 1, 0.03)
                        Rectangle { width: 3; height: parent.height; radius: 2; color: res.tone }
                        ColumnLayout {
                            id: col
                            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 9; topMargin: 7 }
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Dot { kind: res.modelData.state === "ok" ? "" : res.modelData.state === "bad" ? "f" : res.modelData.state === "cancelled" ? "w" : "i" }
                                T { text: res.modelData.label; Layout.fillWidth: true }
                                T { text: res.modelData.detail; color: Theme.dim; font.pixelSize: 11 }
                            }
                            Text {
                                visible: res.modelData.output !== ""
                                text: res.modelData.output
                                color: Theme.dim
                                font.family: res.modelData.state === "cur" ? Theme.mono : "monospace"
                                font.pixelSize: 11
                                wrapMode: Text.WrapAnywhere
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
        footer: [
            T { text: dash.jobNote; color: Theme.dim; font.pixelSize: 11; font.capitalization: Font.MixedCase; wrapMode: Text.Wrap; elide: Text.ElideNone; Layout.fillWidth: true },
            FixBtn {
                // Two clicks to stop: killing an upgrade half-way can leave it
                // half-applied, so the first click only arms the button.
                visible: dash.jobRunning
                enabled: !dash.jobCancelling
                tone: "danger"
                text: dash.jobCancelling ? qsTr("Stopping…") : jobSheet.cancelArmed ? qsTr("Click again to stop") : qsTr("Cancel")
                onClicked: { if (!jobSheet.cancelArmed) { jobSheet.cancelArmed = true; disarm.restart() } else { jobSheet.cancelArmed = false; dash.cancelJob() } }
            },
            FixBtn { text: dash.jobRunning ? qsTr("Hide") : qsTr("Close"); tip: dash.jobRunning ? qsTr("Hide this window — the repair keeps running") : ""; onClicked: jobSheet.close() }
        ]
    }

    // ── update ───────────────────────────────────────────────────────────
    Sheet {
        id: updateSheet
        title: qsTr("Update")
        busy: dash.updateChecking
        sheetWidth: 600
        T {
            Layout.fillWidth: true
            font.capitalization: Font.MixedCase; wrapMode: Text.Wrap; elide: Text.ElideNone
            font.pixelSize: 15; font.bold: true; color: Theme.bright
            text: dash.updateChecking ? qsTr("Checking GitHub…")
                : dash.update.available === "yes" ? qsTr("CopperBSD %1 is available").arg(dash.update.latest)
                : dash.update.available === "no" ? qsTr("CopperBSD is up to date")
                : qsTr("Could not check for a new CopperBSD version")
        }
        KV { k: qsTr("Installed"); v: dash.update.installed || qsTr("unknown") }
        KV { k: qsTr("Latest on GitHub"); v: dash.update.latest || qsTr("unknown") }
        T {
            Layout.fillWidth: true
            font.capitalization: Font.MixedCase; wrapMode: Text.Wrap; elide: Text.ElideNone
            color: Theme.dim; font.pixelSize: 12
            text: dash.update.error === "updater not installed"
                ? qsTr("This system was installed before the updater existed, so the button cannot update it yet. Reinstall from a current ISO, or copy copperbsd-update.sh from the CopperBSD repository to /usr/local/libexec/copperbsd-update.")
                : qsTr("Updating CopperBSD downloads the latest release from github.com/CopperArch/CopperBSD, replaces the media-server project and the dashboard, and re-applies the media stack with your saved profile. Your media, settings and profile are kept. Packages and FreeBSD itself are upgraded separately with “Upgrade packages”.")
        }
        footer: [
            FixBtn { text: qsTr("Check again"); enabled: !dash.updateChecking; onClicked: dash.checkUpdate() },
            Item { Layout.fillWidth: true },
            FixBtn {
                text: qsTr("Upgrade packages")
                tip: dash.fixInfo("pkg_upgrade")
                onClicked: { updateSheet.close(); dash.runFixes([{ id: "pkg_upgrade", args: {}, label: qsTr("Upgrade packages (pkg upgrade)") }], qsTr("Upgrading packages…")) }
            },
            FixBtn {
                tone: "go"
                enabled: dash.update.error !== "updater not installed" && dash.reachable
                text: dash.update.available === "yes" ? qsTr("Update to %1").arg(dash.update.latest) : qsTr("Update CopperBSD")
                tip: dash.fixInfo("copperbsd_update")
                onClicked: { updateSheet.close(); dash.runFixes([{ id: "copperbsd_update", args: {}, label: qsTr("Update CopperBSD from GitHub") }], qsTr("Updating CopperBSD…")) }
            },
            FixBtn { text: qsTr("Close"); onClicked: updateSheet.close() }
        ]
    }

    // ── reboot ───────────────────────────────────────────────────────────
    Sheet {
        id: rebootSheet
        property bool armed: false
        property string note: ""
        title: qsTr("Reboot this machine?")
        sheetWidth: 480
        T {
            Layout.fillWidth: true
            font.capitalization: Font.MixedCase; wrapMode: Text.Wrap; elide: Text.ElideNone
            text: rebootSheet.note !== "" ? rebootSheet.note
                : qsTr("Every jail and stream stops while it restarts. Anything downloading resumes afterwards.")
        }
        footer: [
            Item { Layout.fillWidth: true },
            FixBtn { text: qsTr("Cancel"); onClicked: rebootSheet.close() },
            FixBtn { tone: "danger"; text: qsTr("Yes, reboot now"); enabled: dash.reachable && rebootSheet.note === ""; onClicked: dash.reboot() }
        ]
    }

    // ── change VPN provider ──────────────────────────────────────────────
    Sheet {
        id: vpnSheet
        property bool saving: false
        property string note: ""
        property bool noteOk: false
        title: qsTr("Change VPN provider")
        busy: saving
        sheetWidth: 640
        T {
            Layout.fillWidth: true
            font.capitalization: Font.MixedCase; wrapMode: Text.Wrap; elide: Text.ElideNone
            color: Theme.dim; font.pixelSize: 12
            text: qsTr("Get a WireGuard config from any provider — or from a WireGuard server of your own — then paste the whole file below. Private key, public key, endpoint and any pre-shared key are pulled out of it automatically.")
        }
        RowLayout {
            spacing: 7
            FixBtn { text: qsTr("Proton VPN (free)"); onClicked: dash.openLink("protonvpn_wg") }
            FixBtn { text: qsTr("Windscribe (free)"); onClicked: dash.openLink("windscribe_wg") }
            FixBtn { text: qsTr("Surfshark"); onClicked: dash.openLink("surfshark_wg") }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            radius: 6; color: Theme.panel; border.color: vpnName.activeFocus ? Theme.blue : Theme.edge
            TextInput {
                id: vpnName
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.ink; font.pixelSize: 12; maximumLength: 40; clip: true; selectByMouse: true
                Accessible.name: qsTr("VPN name")
                Text {
                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                    visible: vpnName.text === ""
                    text: qsTr("Name to show on the dashboard (e.g. Mullvad, Home server) — blank to guess")
                    color: Theme.faint; font.pixelSize: 12; elide: Text.ElideRight
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 190
            radius: 6; color: Theme.panel; border.color: vpnText.activeFocus ? Theme.blue : Theme.edge
            QQC2.ScrollView {
                anchors.fill: parent; anchors.margins: 4
                TextEdit {
                    id: vpnText
                    color: Theme.ink; font.family: "monospace"; font.pixelSize: 12
                    wrapMode: TextEdit.NoWrap; selectByMouse: true
                    Accessible.name: qsTr("WireGuard configuration")
                    Text {
                        visible: vpnText.text === ""
                        text: "[Interface]\nPrivateKey = ...\nAddress = 10.2.0.2/32\nDNS = 10.2.0.1\n\n[Peer]\nPublicKey = ...\nEndpoint = vpn.example.com:51820\nAllowedIPs = 0.0.0.0/0, ::/0"
                        color: Theme.faint; font: vpnText.font
                    }
                }
            }
        }
        T {
            visible: vpnSheet.note !== ""
            Layout.fillWidth: true
            font.capitalization: Font.MixedCase; wrapMode: Text.Wrap; elide: Text.ElideNone
            text: vpnSheet.note; color: vpnSheet.noteOk ? Theme.ok : Theme.fail; font.pixelSize: 12
        }
        footer: [
            T { text: qsTr("Restarts the VPN tunnel immediately — qBittorrent/Sonarr/Radarr will briefly drop offline."); color: Theme.dim; font.pixelSize: 11; font.capitalization: Font.MixedCase; wrapMode: Text.Wrap; elide: Text.ElideNone; Layout.fillWidth: true },
            FixBtn { text: qsTr("Cancel"); onClicked: vpnSheet.close() },
            FixBtn {
                tone: "go"
                enabled: !vpnSheet.saving
                text: qsTr("Save & restart tunnel")
                onClicked: {
                    if (vpnText.text.trim() === "") { vpnSheet.note = qsTr("paste a WireGuard config first"); vpnSheet.noteOk = false; return }
                    vpnSheet.saving = true; vpnSheet.note = ""
                    dash.setVpnConfig(vpnText.text, vpnName.text)
                }
            }
        ]
    }

    // ── self-heal schedule ───────────────────────────────────────────────
    Sheet {
        id: schedSheet
        property bool saving: false
        property string note: ""
        property bool noteOk: false
        property string frequency: "daily"
        title: qsTr("Change self-heal schedule")
        busy: saving
        sheetWidth: 480
        RowLayout {
            spacing: 6
            T { text: qsTr("Runs"); color: Theme.dim; Layout.preferredWidth: 60 }
            Repeater {
                model: ["daily", "weekly", "monthly", "yearly"]
                delegate: FixBtn {
                    required property string modelData
                    text: modelData
                    tone: schedSheet.frequency === modelData ? "go" : ""
                    onClicked: schedSheet.frequency = modelData
                }
            }
        }
        RowLayout {
            spacing: 6
            T { text: qsTr("At"); color: Theme.dim; Layout.preferredWidth: 60 }
            Rectangle {
                implicitWidth: 90; implicitHeight: 28
                radius: 6; color: Theme.panel; border.color: schedTime.activeFocus ? Theme.blue : Theme.edge
                TextInput {
                    id: schedTime
                    anchors.fill: parent
                    horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                    color: Theme.ink; font.pixelSize: 13; selectByMouse: true
                    text: "03:00"
                    inputMask: "99:99"
                    Accessible.name: qsTr("Time of day, 24-hour")
                }
            }
            T { text: qsTr("24-hour clock"); color: Theme.faint; font.pixelSize: 11 }
        }
        T {
            visible: schedSheet.note !== ""
            Layout.fillWidth: true
            font.capitalization: Font.MixedCase; wrapMode: Text.Wrap; elide: Text.ElideNone
            text: schedSheet.note; color: schedSheet.noteOk ? Theme.ok : Theme.fail; font.pixelSize: 12
        }
        footer: [
            Item { Layout.fillWidth: true },
            FixBtn { text: qsTr("Cancel"); onClicked: schedSheet.close() },
            FixBtn {
                tone: "go"; text: qsTr("Save"); enabled: !schedSheet.saving
                onClicked: { schedSheet.saving = true; schedSheet.note = ""; dash.setSchedule(schedSheet.frequency, schedTime.text) }
            }
        ]
    }

    // ── about ────────────────────────────────────────────────────────────
    Sheet {
        id: aboutSheet
        title: qsTr("About this system")
        sheetWidth: 560
        T {
            Layout.fillWidth: true
            font.capitalization: Font.MixedCase; wrapMode: Text.Wrap; elide: Text.ElideNone
            font.pixelSize: 15; color: Theme.bright
            text: qsTr("CopperBSD dashboard — version %1").arg(dash.update.installed && dash.update.installed !== "unknown" ? dash.update.installed : qsTr("unknown"))
        }
        KV { k: qsTr("Host"); v: sys.hostname }
        KV { k: qsTr("System"); v: sys.osName + " " + sys.kernel }
        KV { k: qsTr("Processor"); v: sys.cpuModel; v2: "(" + sys.cpuCores + ")" }
        KV { k: qsTr("Uptime"); v: sys.uptime }
        T {
            Layout.fillWidth: true
            font.capitalization: Font.MixedCase; wrapMode: Text.Wrap; elide: Text.ElideNone
            color: Theme.dim; font.pixelSize: 12
            text: qsTr("A FreeBSD media server: jails for each app, a WireGuard VPN jail with a pf kill-switch, and a nightly self-heal routine. Repairs on this dashboard are a closed list run by a loopback-only service. You are responsible for how the system is used, including complying with the laws that apply to you.")
        }
        footer: [
            Item { Layout.fillWidth: true },
            FixBtn { text: qsTr("Check for updates"); onClicked: { aboutSheet.close(); dash.checkUpdate(); updateSheet.open() } },
            FixBtn { text: qsTr("Back to dashboard"); onClicked: aboutSheet.close() }
        ]
    }
}
