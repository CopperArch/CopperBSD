pragma Singleton

import QtQuick

/*! CopperBSD design tokens. Same palette as the installer so the two read as
    one product. Pages draw their own dark panels, so the dashboard looks the
    same under a light or a dark Plasma colour scheme. */
QtObject {
    readonly property color accent:     "#c86a3a"   // copper
    readonly property color accentText: "#ffffff"
    readonly property color window:     "#1b1e24"
    readonly property color surface:    "#232730"
    readonly property color surfaceAlt: "#2b303b"
    readonly property color border:     "#394150"
    readonly property color text:       "#eef1f6"
    readonly property color textDim:    "#9aa4b2"
    readonly property color danger:     "#e2574c"
    readonly property color warn:       "#e3a008"
    readonly property color ok:         "#4caf7d"
    readonly property int gap:    16
    readonly property int gapLg:  28
    readonly property int radius: 12
}
