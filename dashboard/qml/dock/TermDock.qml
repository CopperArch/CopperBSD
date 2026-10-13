import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import CopperDashboard

/*! The terminal dock: Claude Code, the other AI panes and the system panes,
    beside the dashboard — the same dock, picker, ask box and width buttons as
    the CopperArch Linux/FreeBSD web dashboard. The terminal is ttyd
    (dashboard-pane.sh decides what runs in it); the picker's contents and
    prices come from the repair server.

    Only the dock's width changes between ¼ / ½ / ¾ / full, so a running
    session survives every resize. "off" stops it. Fills the page; `taken` is
    how much of the page's width the terminal covers right now. */
Item {
    id: dock

    /*! Percent of the page the terminal takes: 0, 25, 50, 75 or 100. */
    property int w: 0
    readonly property real taken: side.width
    readonly property var widths: [0, 25, 50, 75, 100]

    /*! Pane id that is running, or will run when the dock is opened. */
    property string pane: ""
    property string paneLabel: ""
    /*! True once a program has actually been started in the terminal. */
    property bool loaded: false
    property bool asking: false
    /*! What the terminal shows: a ttyd address, or "" for nothing. */
    property string target: ""
    readonly property var term: termLoader.item

    readonly property var groupOrder: ["agent", "paid", "free", "local", "system"]
    readonly property var groupLabel: ({ agent: qsTr("Agent"), paid: qsTr("Paid"), free: qsTr("Free"),
                                         local: qsTr("Local"), system: qsTr("System") })

    Settings {
        id: saved
        category: "dock"
        property int termWidth: 0
        property string termPane: "claude"
        property string askTarget: "ask"
    }

    function labelOf(id) {
        for (const p of dash.panes)
            if (p.id === id)
                return p.label
        for (const t of dash.askTargets)
            if (t.id === id)
                return qsTr("Ask %1").arg(t.label)
        return id === "claude" ? "Claude Code" : id === "shell" ? qsTr("Shell") : id
    }

    function apply(next, remember) {
        w = next
        if (remember)
            saved.termWidth = next
        // "off" means stop, not just hide: dropping the page closes ttyd's
        // connection, which hangs up whatever was running in the pane.
        if (w === 0 && loaded) {
            target = ""
            loaded = false
        }
    }

    function openPane(id, label, extra, reveal) {
        pane = id
        loaded = true
        boot.stop()
        if (!extra)
            saved.termPane = id          // one-off asks are not remembered
        paneLabel = label || labelOf(id)
        let url = dash.terminalUrl + "?arg=" + encodeURIComponent(id)
        if (extra)
            url += "&arg=" + encodeURIComponent(extra)
        if (target === url && term)
            term.retry()                 // same pane picked again: a new session
        else
            target = url
        // Picking a pane implies wanting to see it.
        if (reveal && w === 0)
            apply(50, true)
    }

    /*! Start the remembered pane — or, when this machine does not have it,
        the first one it does have. */
    function bootCurrent() {
        if (loaded)
            return
        if (!dash.panesLoaded && !boot.gaveUp) {
            boot.restart()               // the pane list is still on its way
            return
        }
        const wanted = pane || saved.termPane
        let id = wanted
        if (dash.panesLoaded && !dash.panes.some(p => p.id === id)) {
            id = "shell"
            for (const g of groupOrder) {
                const first = dash.panes.find(p => p.group === g)
                if (first) { id = first.id; break }
            }
        }
        openPane(id, "", "", false)
        // A stand-in is not a choice: the remembered pane comes back by
        // itself once its program is installed.
        saved.termPane = wanted
    }

    function setWidth(next) {
        apply(next, true)
        // Opening the dock counts as wanting to use it; the width buttons
        // never restart a session that is already running.
        if (next > 0 && !loaded)
            bootCurrent()
    }

    Timer {
        id: boot
        property bool gaveUp: false
        interval: 2500
        onTriggered: { gaveUp = true; if (dock.w > 0) dock.bootCurrent() }
    }
    Connections {
        target: dash
        function onPanesChanged() {
            if (dock.w > 0 && !dock.loaded)
                dock.bootCurrent()
            else if (dock.pane !== "" && !dock.paneLabel.startsWith(qsTr("Ask ")))
                dock.paneLabel = dock.labelOf(dock.pane)
        }
    }

    // Ctrl+` steps through the widths. Inside the terminal the keystroke
    // belongs to the shell, which is why the control strip is always visible.
    Shortcut {
        sequences: ["Ctrl+`"]
        onActivated: dock.setWidth(dock.widths[(dock.widths.indexOf(dock.w) + 1) % dock.widths.length])
    }

    Component.onCompleted: {
        pane = saved.termPane
        paneLabel = labelOf(pane)
        const start = startDockWidth > 0 ? startDockWidth : saved.termWidth
        w = widths.includes(start) ? start : 0
        // The dock was left open: start its pane now.
        if (w > 0)
            bootCurrent()
    }

    // ── the terminal ─────────────────────────────────────────────────────
    Rectangle {
        id: side
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: Math.round(dock.width * dock.w / 100)
        visible: width > 0
        clip: true
        color: "#0b0f16"
        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }

        // The web view exists only while the dock is open, so a closed dock
        // costs nothing — and closing it is what drops the session.
        Loader {
            id: termLoader
            anchors { fill: parent; leftMargin: 1 }
            active: dock.w > 0 || side.width > 0
            sourceComponent: TermView {
                base: dash.terminalUrl
                target: dock.target
                visible: available && !failed
            }
        }
        Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.edge }

        // ttyd comes up within a minute of being installed or stopped.
        Timer { interval: 5000; repeat: true; running: dock.term !== null && dock.term.failed && dock.w > 0; onTriggered: dock.term.retry() }
        ColumnLayout {
            id: note
            readonly property bool built: dock.term !== null && dock.term.available
            visible: dock.term !== null && (!dock.term.available || dock.term.failed)
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 440)
            spacing: 12
            T {
                Layout.fillWidth: true
                text: note.built ? qsTr("The terminal is not answering") : qsTr("Terminal dock not built in")
                color: Theme.warn; font.pixelSize: 14; font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            T {
                Layout.fillWidth: true
                wrapMode: Text.Wrap; elide: Text.ElideNone
                font.capitalization: Font.MixedCase
                horizontalAlignment: Text.AlignHCenter
                color: Theme.dim
                text: note.built
                    ? qsTr("Nothing is listening on %1. The terminal service (ttyd) is installed with the media server and is restarted within a minute if it stops; this retries by itself.").arg(dash.terminalUrl)
                    : qsTr("This dashboard was built without QtWebEngine, which draws the terminal. Install qt6-webengine and rebuild the dashboard (Update → Update CopperBSD).")
            }
            FixBtn {
                visible: note.built
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Retry now")
                onClicked: dock.term.retry()
            }
        }
    }

    // ── control strip ────────────────────────────────────────────────────
    // Pinned bottom right and always on top: at full width it is the only
    // way back, because the terminal covers the dashboard's header.
    Rectangle {
        id: ctl
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 10; bottomMargin: 8 }
        width: strip.implicitWidth + 6
        height: strip.implicitHeight + 6
        radius: 9
        color: Qt.rgba(10 / 255, 15 / 255, 22 / 255, 0.92)
        border.color: Theme.edge

        RowLayout {
            id: strip
            anchors.centerIn: parent
            spacing: 2

            DockBtn {
                id: paneBtn
                accent: true
                align: Text.AlignLeft
                text: (dock.paneLabel || "Claude Code") + "  ▾"
                tip: qsTr("Choose what runs in the terminal")
                Layout.minimumWidth: 104
                Layout.maximumWidth: 230
                onClicked: {
                    if (menu.opened) {
                        menu.close()
                    } else {
                        dash.loadPanes()     // prices and the Free section change nightly
                        menu.open()
                    }
                }

                QQC2.Popup {
                    id: menu
                    y: -height - 6
                    width: 290
                    height: Math.min(Math.max(rowsCol.implicitHeight, 30) + 8, dock.height * 0.7)
                    padding: 4
                    margins: 6
                    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent
                    background: Rectangle { color: "#0d131c"; radius: 9; border.color: Theme.edge }
                    // Sections in a fixed order: agents, then the AI panes by
                    // who pays for them, then local models, then system tools.
                    readonly property var rows: {
                        const out = []
                        for (const g of dock.groupOrder) {
                            const inGroup = dash.panes.filter(p => p.group === g)
                            if (inGroup.length)
                                out.push({ head: true, text: dock.groupLabel[g] || g })
                            for (const p of inGroup)
                                out.push({ head: false, id: p.id, label: p.label,
                                           text: p.price ? p.label + " — " + p.price : p.label })
                        }
                        return out
                    }
                    contentItem: Flickable {
                        id: list
                        clip: true
                        contentHeight: rowsCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        QQC2.ScrollBar.vertical: ThinScroll {}
                        Column {
                            id: rowsCol
                            width: list.width
                            Repeater {
                                model: menu.rows
                                Loader {
                                    required property var modelData
                                    width: rowsCol.width
                                    sourceComponent: modelData.head ? headRow : paneRow
                                    Component {
                                        id: headRow
                                        T {
                                            text: modelData.text
                                            color: Theme.faint
                                            font.pixelSize: 10; font.letterSpacing: 1
                                            leftPadding: 9; topPadding: 7; bottomPadding: 2
                                        }
                                    }
                                    Component {
                                        id: paneRow
                                        DockBtn {
                                            text: modelData.text
                                            align: Text.AlignLeft
                                            current: modelData.id === dock.pane
                                            onClicked: { menu.close(); dock.openPane(modelData.id, modelData.label, "", true) }
                                        }
                                    }
                                }
                            }
                        }
                        T {
                            visible: menu.rows.length === 0
                            anchors.centerIn: parent
                            text: dash.reachable ? qsTr("Loading…") : qsTr("Status service not answering")
                            color: Theme.dim; font.pixelSize: 11
                        }
                    }
                }
            }

            DockBtn {
                text: qsTr("Ask")
                tip: qsTr("Ask an AI a question")
                current: dock.asking
                onClicked: {
                    dock.asking = !dock.asking
                    if (dock.asking) {
                        dash.loadAskTargets()
                        askInput.forceActiveFocus()
                    }
                }
            }
            RowLayout {
                id: askForm
                visible: dock.asking
                spacing: 3
                // Who answers: every model the server offers for one-off
                // questions, with tonight's price. Clicking steps through them.
                readonly property var targets: dash.askTargets.length ? dash.askTargets
                                                                      : [{ id: "ask", label: "Claude", price: null }]
                readonly property var target: targets.find(t => t.id === saved.askTarget) || targets[0]
                DockBtn {
                    text: askForm.target.label
                    tip: qsTr("Ask %1").arg(askForm.target.label) + (askForm.target.price ? " (" + askForm.target.price + ")" : "")
                           + qsTr(" — click for the next model")
                    onClicked: {
                        const i = askForm.targets.findIndex(t => t.id === askForm.target.id)
                        saved.askTarget = askForm.targets[(i + 1) % askForm.targets.length].id
                        askInput.forceActiveFocus()
                    }
                }
                Rectangle {
                    implicitWidth: 230
                    implicitHeight: askInput.implicitHeight + 8
                    radius: 6
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: askInput.activeFocus ? Theme.blue : Theme.edge
                    TextInput {
                        id: askInput
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 4; bottomMargin: 4 }
                        color: Theme.ink
                        font.family: Theme.mono; font.pixelSize: 12
                        clip: true
                        selectByMouse: true
                        selectionColor: Theme.tint(Theme.blue, 0.4)
                        Keys.onEscapePressed: dock.asking = false
                        onAccepted: {
                            const q = text.trim()
                            if (q === "")
                                return
                            const t = askForm.target
                            dock.openPane(t.id, qsTr("Ask %1").arg(t.label), q, true)
                            text = ""
                            dock.asking = false
                        }
                        Text {
                            visible: askInput.text === ""
                            text: qsTr("ask…")
                            color: Theme.faint
                            font: askInput.font
                        }
                    }
                }
            }

            Rectangle { Layout.fillHeight: true; Layout.margins: 2; Layout.leftMargin: 3; Layout.rightMargin: 3; implicitWidth: 1; color: Theme.edge }

            Repeater {
                model: [{ w: 0, t: qsTr("off") }, { w: 25, t: "¼" }, { w: 50, t: "½" }, { w: 75, t: "¾" }, { w: 100, t: qsTr("full") }]
                DockBtn {
                    required property var modelData
                    text: modelData.t
                    on: dock.w === modelData.w
                    tip: modelData.w === 0 ? qsTr("Close the terminal")
                                           : qsTr("Terminal: %1% of the window").arg(modelData.w)
                    onClicked: dock.setWidth(modelData.w)
                }
            }
        }
    }
}
