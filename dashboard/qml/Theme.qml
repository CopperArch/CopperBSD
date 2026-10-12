pragma Singleton

import QtQuick

/*! CopperBSD design tokens. The dashboard uses the same palette, fonts and
    proportions as the CopperArch Linux/FreeBSD web dashboard so the editions
    read as one product. Pages draw their own dark panels, so it looks the
    same under a light or a dark Plasma colour scheme. */
QtObject {
    // ── dashboard palette (mirrors the web dashboard's CSS variables) ──
    readonly property color bg:      "#0a0e14"
    readonly property color bg2:     "#0e141c"
    readonly property color panel:   Qt.rgba(16 / 255, 22 / 255, 32 / 255, 0.88)
    readonly property color edge:    Qt.rgba(120 / 255, 160 / 255, 220 / 255, 0.14)
    readonly property color edgeHi:  Qt.rgba(120 / 255, 160 / 255, 220 / 255, 0.24)
    readonly property color ink:     "#c8d6e8"
    readonly property color dim:     "#7688a0"
    readonly property color faint:   "#4a586c"
    readonly property color bright:  "#eaf2ff"
    readonly property color fail:    "#f4523b"
    readonly property color todo:    "#4a9eff"
    readonly property color blue:    "#5ac8fa"
    readonly property color copper:  "#c2703d"
    readonly property color brandGray: "#9aa5b1"
    readonly property string mono:      "Rajdhani"
    readonly property string brandFont: "Orbitron"

    // ── names the launcher/system pages use ──
    readonly property color accent:     "#c86a3a"   // copper
    readonly property color accentText: "#ffffff"
    readonly property color window:     bg
    readonly property color surface:    "#101620"
    readonly property color surfaceAlt: "#18212e"
    readonly property color border:     "#243145"
    readonly property color text:       bright
    readonly property color textDim:    dim
    readonly property color danger:     fail
    readonly property color warn:       "#e3a008"
    readonly property color ok:         "#3fb950"
    readonly property int gap:    16
    readonly property int gapLg:  28
    readonly property int radius: 12

    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    /*! 1536 -> "1.5K" — same rounding as the web dashboard. */
    function human(n, unit) {
        n = Number(n) || 0
        unit = unit || 1024
        const u = ["B", "K", "M", "G", "T", "P"]
        for (let i = 0; i < u.length; ++i) {
            if (Math.abs(n) < unit)
                return (i < 2 ? n.toFixed(0) : n.toFixed(1)) + u[i]
            n /= unit
        }
        return n.toFixed(1) + "E"
    }
    function dur(sec) {
        sec = Math.max(0, Math.floor(sec || 0))
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
        return d ? d + "d " + h + "h" : h ? h + "h " + m + "m" : m + "m"
    }
    function num(v, digits) { return (Number(v) || 0).toFixed(digits || 0) }
}
