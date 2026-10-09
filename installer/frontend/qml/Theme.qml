pragma Singleton

import QtQuick

/*! Shared design tokens for the installer. Single source of colour/spacing so
    the pages read as one system (KDE Breeze-adjacent, CopperArch accent). */
QtObject {
    // Brand
    readonly property color accent:      "#c86a3a"   // copper
    readonly property color accentText:  "#ffffff"

    // Surfaces (dark; the live session runs a dark Plasma by default)
    readonly property color window:      "#1b1e24"
    readonly property color surface:      "#232730"
    readonly property color surfaceAlt:   "#2b303b"
    readonly property color border:       "#394150"

    // Text
    readonly property color text:         "#eef1f6"
    readonly property color textDim:      "#9aa4b2"
    readonly property color danger:       "#e2574c"
    readonly property color ok:           "#4caf7d"

    // Metrics
    readonly property int   gap:          16
    readonly property int   gapLg:        28
    readonly property int   radius:       10
    readonly property int   sidebarW:     260

    readonly property int   fontH1:       28
    readonly property int   fontH2:       20
    readonly property int   fontBody:     14
}
