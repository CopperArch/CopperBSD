#!/bin/sh
# desktop-build-test.sh — verify every desktop group resolves and the compositors
# actually run. Runs in the FreeBSD builder/CI (needs pkg). Emits per-item
# results for the §20 report. NOT runnable in the Linux authoring sandbox.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/../packages/desktops.conf"
[ "$(uname -s)" = FreeBSD ] || { echo "NOT TESTED: desktop build test requires FreeBSD"; exit 0; }

fail=0
for g in kde gnome xfce niri mangowc; do
    echo "== group: $g =="
    if env ASSUME_ALWAYS_YES=YES pkg install -n $(desktop_pkgs "$g") >/dev/null 2>&1; then
        echo "  PASS pkg resolves: $g"
    else
        echo "  FAIL pkg cannot resolve: $g"; fail=1
    fi
done

echo "== compositor smoke (install + --version) =="
for p in "niri:niri" "quickshell:quickshell" "mangowc:mango"; do
    port=${p%%:*}; bin=${p##*:}
    env ASSUME_ALWAYS_YES=YES pkg install -y "$port" >/dev/null 2>&1 || { echo "  FAIL install $port"; fail=1; continue; }
    if "$bin" --version >/dev/null 2>&1 || "$bin" --help >/dev/null 2>&1; then
        echo "  PASS $bin runs ($("$bin" --version 2>/dev/null | head -1))"
    else
        echo "  FAIL $bin present but --version/--help failed"; fail=1
    fi
done

echo "== session files present =="
for s in niri mangowc; do
    [ -f "$HERE/../installer/configuration/desktop/wayland-sessions/$s.desktop" ] \
        && echo "  PASS $s.desktop" || { echo "  FAIL $s.desktop"; fail=1; }
done
[ "$fail" = 0 ] && echo "DESKTOP BUILD TEST: all passed" || echo "DESKTOP BUILD TEST: failures above"
exit $fail
