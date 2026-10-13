import QtQuick

/*! Stand-in used when the dashboard was built without QtWebEngine: the dock
    has nothing to draw a terminal with and says so. */
Item {
    property string base: ""
    property string target: ""
    readonly property bool available: false
    property bool failed: false
    function retry() {}
}
