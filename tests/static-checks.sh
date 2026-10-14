#!/bin/sh
# static-checks.sh — validation that runs on ANY host (no FreeBSD needed):
# shell syntax, Python compile, YAML parse, CMake↔file consistency, overlay and
# installerconfig sanity, pinned-commit record. Exits non-zero on any failure.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$HERE")
cd "$ROOT"

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

echo "== shell syntax (sh -n) =="
for f in $(find . -name '*.sh' -not -path './freebsd/src-pinned/*' -not -path './.git/*'); do
    # a script that asks for bash is checked with bash (skipped where there is none)
    if head -1 "$f" | grep -q bash; then
        command -v bash >/dev/null 2>&1 || { ok "$f (bash script; no bash here to check it)"; continue; }
        if bash -n "$f" 2>/dev/null; then ok "$f"; else bad "$f"; fi
        continue
    fi
    if sh -n "$f" 2>/dev/null; then ok "$f"; else bad "$f"; fi
done

echo "== POSIX-sh scripts have no bash-only shebang mismatch =="
# (bash scripts are allowed if they declare bash; flag sh scripts using bashisms we care about)
offender=""
for f in $(find . -name '*.sh' -not -path './freebsd/*' -not -path './.git/*' -not -path './tests/static-checks.sh'); do
    head -1 "$f" | grep -q '#!/bin/sh' || continue
    if grep -nE '\[\[ |declare -|local -A' "$f" >/dev/null 2>&1; then offender="$f"; break; fi
done
[ -z "$offender" ] && ok "no sh/bash shebang mismatches" || bad "bash-only syntax in $offender"

echo "== Python compiles =="
if command -v python3 >/dev/null 2>&1; then
    for f in $(find . -name '*.py' -not -path './freebsd/src-pinned/*' -not -path './.git/*'); do
        if python3 -m py_compile "$f" 2>/dev/null; then ok "$f"; else bad "$f"; fi
    done
else bad "python3 not available to compile-check"; fi

echo "== YAML parses =="
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
    for f in $(find . -name '*.yaml' -o -name '*.yml' | grep -v freebsd/src-pinned | grep -v '/.git/'); do
        if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$f" 2>/dev/null; then ok "$f"; else bad "$f"; fi
    done
else printf '  \033[33mSKIP\033[0m YAML (pyyaml not installed)\n'; fi

echo "== installer: every CMake-referenced file exists =="
cm=installer/frontend/CMakeLists.txt
if [ -f "$cm" ]; then
    miss=0
    for f in $(grep -oE '(qml/[A-Za-z/]+\.qml|src/[A-Za-z]+\.(cpp|h))' "$cm" | sort -u); do
        [ -f "installer/frontend/$f" ] || { bad "missing $f"; miss=1; }
    done
    [ "$miss" = 0 ] && ok "all CMake QML_FILES/SOURCES present"
else bad "installer CMakeLists.txt missing"; fi

echo "== installerconfig is a valid scripted-install (preamble + #!/bin/sh) =="
ic=installer/configuration/installerconfig
if [ -f "$ic" ] && grep -q '^DISTRIBUTIONS=' "$ic" && grep -q '^#!/bin/sh' "$ic" \
   && grep -q 'ZFSBOOT_' "$ic"; then ok "installerconfig structure"; else bad "installerconfig structure"; fi

echo "== native dashboard (Qt/QML; web view only for the terminal dock) =="
for f in dashboard/CMakeLists.txt dashboard/src/main.cpp dashboard/qml/Main.qml \
         dashboard/data/copper-dashboard.desktop dashboard/assets/logo.png; do
    [ -f "$f" ] && ok "$f" || bad "$f missing"
done
# The one web view is the terminal dock (ttyd); everything else is native QML,
# and the dashboard must still build where QtWebEngine is not installed.
if grep -rliE 'WebEngine|QtWebView|chromium|electron' dashboard/src dashboard/qml \
        | grep -vE '^dashboard/(src/main\.cpp|qml/dock/)' | grep -q .; then
    bad "a browser engine is used outside the terminal dock"
else ok "browser engine confined to the terminal dock"; fi
if grep -q 'QUIET COMPONENTS WebEngineQuick' dashboard/CMakeLists.txt \
   && [ -f dashboard/qml/dock/none/TermView.qml ] \
   && ! grep -q '^import QtWebEngine' dashboard/qml/dock/none/TermView.qml; then
    ok "dashboard builds without QtWebEngine (dock-less fallback)"
else bad "QtWebEngine must stay optional for the dashboard build"; fi
for f in dashboard/qml/dock/TermDock.qml dashboard/qml/dock/web/TermView.qml \
         project/templates/dashboard/dashboard-pane.sh project/templates/dashboard/ai-panes-check.py; do
    [ -f "$f" ] && ok "$f" || bad "$f missing (terminal dock)"
done
grep -q 'qt6-webengine' installer/configuration/firstboot.sh \
    && grep -q 'qt6-webengine' installer/configuration/copperbsd-update.sh \
    && ok "first boot and the updater install qt6-webengine" || bad "qt6-webengine not installed for the dock"
grep -q -- '--interface 127.0.0.1' project/lib/distro.py && grep -q -- '--check-origin' project/lib/distro.py \
    && ok "terminal bridge is loopback-only and origin-checked" || bad "ttyd must be loopback-only with --check-origin"
[ -f project/templates/dashboard/index.html ] && bad "old web dashboard page still present" || ok "old web dashboard page removed"

echo "== media project: CopperBSD's step changes still match upstream =="
if command -v python3 >/dev/null 2>&1; then
    if python3 -c "
import sys; sys.path.insert(0, 'project')
from lib.steps import ORDER
t = [title for title, _ in ORDER]
assert 'Dashboard backend' in t and 'Media storage' in t, t
assert not {'Konsole theme', 'Desktop dashboard', 'Storage auto-pooling'} & set(t), t
" 2>/dev/null; then ok "project/lib/distro.py applies to project/lib/steps.py"
    else bad "project/lib/distro.py is out of date with project/lib/steps.py"; fi
fi
[ -f project/UPSTREAM ] && ok "project/UPSTREAM records the synced version" || bad "project/UPSTREAM missing (run tools/sync-project.sh)"

echo "== live overlay present =="
for f in etc/copperarch-live \
         usr/local/etc/sddm.conf.d/copperarch-live.conf \
         usr/local/share/wayland-sessions/copperarch-installer.desktop \
         usr/local/share/xsessions/copperarch-installer-x11.desktop \
         usr/local/bin/copperarch-installer-x11-session \
         usr/local/etc/rc.d/copperarch_diag \
         usr/local/etc/doas.conf \
         usr/local/etc/rc.d/copperarch_liveuser \
         usr/local/bin/copperarch-installer-session; do
    [ -f "overlays/$f" ] && ok "overlay $f" || bad "overlay $f missing"
done

echo "== scripts are executable in git (rc.d/session wrappers fail silently otherwise) =="
for f in overlays/usr/local/etc/rc.d/copperarch_liveuser overlays/usr/local/etc/rc.d/copperarch_diag \
         overlays/usr/local/bin/copperarch-installer-x11-session overlays/usr/local/bin/copperarch-installer-session \
         installer/backend/copperarch-install.sh installer/configuration/firstboot.sh \
         installer/configuration/copperbsd-update.sh build/in-vm-build.sh; do
    if git ls-files -s "$f" 2>/dev/null | grep -q '^100755'; then ok "+x $f"
    elif [ ! -d .git ] && [ -x "$f" ]; then ok "+x $f"
    else bad "$f is not executable (git update-index --chmod=+x $f)"; fi
done

echo "== live session sets a default cursor =="
grep -q 'xsetroot -cursor_name left_ptr' overlays/usr/local/bin/copperarch-installer-x11-session \
    && ok "x11 installer session sets the root cursor" || bad "x11 installer session has no default cursor (pointer invisible until it crosses a button)"

echo "== pinned FreeBSD commit recorded =="
if [ -f freebsd/COMMIT ] && grep -qE '^[0-9a-f]{40}$' freebsd/COMMIT; then
    ok "pinned commit $(cat freebsd/COMMIT)"; else bad "freebsd/COMMIT missing or malformed"; fi

echo "== vendored FreeBSD release tooling present (mkisoimages.sh) =="
[ -f "freebsd/src-pinned/release/$(uname -m 2>/dev/null | sed 's/x86_64/amd64/')/mkisoimages.sh" ] \
   || [ -f freebsd/src-pinned/release/amd64/mkisoimages.sh ] \
   && ok "mkisoimages.sh vendored" || bad "mkisoimages.sh not vendored"

echo
echo "== RESULT: $pass passed, $fail failed =="
[ "$fail" = 0 ]
