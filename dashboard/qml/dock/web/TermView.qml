import QtQuick
import QtWebEngine

/*! The terminal itself: a web view onto ttyd, the same bridge the Linux
    dashboard embeds as an iframe. It only ever shows the loopback terminal —
    any other address is refused, and nothing opens in a new window. */
Item {
    id: root
    /*! ttyd's address; nothing else may be loaded. */
    property string base: ""
    /*! What to show: a ttyd URL, or "" for nothing (which hangs up the session). */
    property string target: ""
    readonly property bool available: true
    /*! ttyd did not answer. */
    property bool failed: false

    function retry() { root.failed = false; view.reload() }

    WebEngineView {
        id: view
        anchors.fill: parent
        url: root.target === "" ? "about:blank" : root.target
        backgroundColor: "#0b0f16"
        // The terminal's scrollbar, drawn like the dashboard's own instead of
        // the engine's light default.
        userScripts.collection: [{
            name: "copper-scrollbar",
            injectionPoint: WebEngineScript.DocumentReady,
            worldId: WebEngineScript.ApplicationWorld,
            sourceCode: "const s = document.createElement('style');"
                + "s.textContent = '::-webkit-scrollbar{width:8px;height:8px;background:#0b0f16}"
                + "::-webkit-scrollbar-thumb{background:rgba(90,200,250,.28);border-radius:4px}"
                + "::-webkit-scrollbar-corner{background:#0b0f16}';"
                + "document.head.appendChild(s);"
        }]
        // Copy and paste between the terminal and the desktop.
        settings.javascriptCanAccessClipboard: true
        settings.javascriptCanPaste: true
        settings.focusOnNavigationEnabled: true

        onNavigationRequested: request => {
            const u = request.url.toString()
            if (u !== "about:blank" && !u.startsWith(root.base))
                request.reject()
        }
        onNewWindowRequested: request => {}
        // ttyd asks "leave this page?" once something was typed. Switching pane
        // or closing the dock is the answer; a dialog here would only block it.
        onJavaScriptDialogRequested: request => {
            request.accepted = true
            request.dialogAccept()
        }
        onContextMenuRequested: request => { request.accepted = true }
        onLoadingChanged: info => {
            if (info.status === WebEngineView.LoadFailedStatus)
                root.failed = root.target !== ""
            else if (info.status === WebEngineView.LoadSucceededStatus)
                root.failed = false
        }
    }
    onTargetChanged: failed = false
}
