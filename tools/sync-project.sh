#!/bin/sh
# sync-project.sh <freebsd-media-setup checkout> — refresh project/ from the
# FreeBSD media-server project it is a copy of.
#
# project/ is NOT edited by hand any more. Everything in it comes from upstream
# (github.com/CopperArch/freebsd-media-setup-with-dash) except the few files
# listed in OWNED below, which are CopperBSD's own and survive every sync.
# CopperBSD's behaviour differences live in one of them, project/lib/distro.py,
# which upstream's lib/steps.py loads when it is present.
#
# Two mechanical changes are made to the copy:
#   * python3.11 -> python3.12 (CopperBSD ships python312 + py312-pyyaml)
#   * the browser dashboard and the KDE theming are left out; CopperBSD has a
#     native dashboard (dashboard/) and its own desktop choices
#
# Runs on any host (POSIX sh + tar). Finishes with a dry run of the installer.
set -eu

UP="${1:?usage: sync-project.sh <path to a freebsd-media-setup checkout>}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$HERE")
DST="$ROOT/project"

[ -f "$UP/install.py" ] && [ -f "$UP/lib/steps.py" ] && [ -f "$UP/stacks/stack.yaml" ] \
    || { echo "!! $UP is not a freebsd-media-setup checkout" >&2; exit 1; }
grep -q 'from .distro import adjust_order' "$UP/lib/steps.py" \
    || { echo "!! upstream lib/steps.py has no distro hook; update the checkout" >&2; exit 1; }

# CopperBSD's own files inside project/ (never taken from upstream).
OWNED="lib/distro.py profiles/unattended.yaml ARCHITECTURE.md build-iso.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/copperbsd-sync.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

( cd "$UP" && tar -cf - \
    --exclude '__pycache__' --exclude '*.pyc' \
    --exclude 'templates/kde-theme' \
    --exclude 'templates/dashboard/index.html' \
    --exclude 'templates/dashboard/fonts' \
    --exclude 'templates/dashboard/CopperArch.colorscheme' \
    --exclude 'templates/dashboard/CopperArch.profile' \
    --exclude 'templates/dashboard/copperarch-konsole-bg.png' \
    --exclude 'templates/dashboard/copperarch-wallpaper.png' \
    --exclude 'templates/dashboard/kde-panel-defaults.sh' \
    --exclude 'templates/dashboard/dashboard-pane.sh' \
    --exclude 'templates/dashboard/ai-panes-check.py' \
    --exclude 'templates/dashboard/status-dashboard-install.sh' \
    --exclude 'templates/dashboard/status-dashboard-run.sh' \
    --exclude 'templates/dashboard/status-dashboard-show.sh' \
    install.py rebuild lib stacks vpn templates profiles/example.yaml ) \
    | tar -xf - -C "$TMP"

for f in $OWNED; do
    [ -e "$DST/$f" ] || { echo "!! CopperBSD file project/$f is missing" >&2; exit 1; }
    mkdir -p "$TMP/$(dirname "$f")"
    cp -p "$DST/$f" "$TMP/$f"
done

# python3.11 -> python3.12, except where 3.11 is the point: the Seerr build
# needs distutils (gone in 3.12), inside its own jail.
find "$TMP" -type f \( -name '*.py' -o -name '*.sh' -o -name '*.md' -o -name rebuild \) \
    -not -path "$TMP/templates/seerr-build/*" | while IFS= read -r f; do
    if grep -q 'python3\.11\|python311\|py311' "$f"; then
        sed -e 's/python3\.11/python3.12/g' -e 's/python311/python312/g' \
            -e 's/py311/py312/g' "$f" > "$f.sync" && cat "$f.sync" > "$f" && rm -f "$f.sync"
    fi
done

# Where this copy came from, for the next person to sync.
{
    printf 'source:  github.com/CopperArch/freebsd-media-setup-with-dash\n'
    printf 'version: %s\n' "$(cat "$UP/VERSION" 2>/dev/null || echo unknown)"
    printf 'commit:  %s\n' "$(git -C "$UP" rev-parse HEAD 2>/dev/null || echo unknown)"
    printf 'synced by tools/sync-project.sh; do not edit the copied files here\n'
} > "$TMP/UPSTREAM"

rm -rf "$DST"
mv "$TMP" "$DST"
chmod 755 "$DST"
trap - EXIT INT TERM
echo ">> project/ refreshed from $(sed -n 's/^version: //p' "$DST/UPSTREAM") ($(sed -n 's/^commit:  //p' "$DST/UPSTREAM" | cut -c1-7))"

PY=$(command -v python3.12 || command -v python3 || true)
if [ -n "$PY" ] && "$PY" -c 'import yaml' 2>/dev/null; then
    echo ">> dry run of the first-boot install"
    "$PY" "$DST/install.py" --cli --profile "$DST/profiles/unattended.yaml" --dry-run --yes \
        | grep -E '^---|ERR|Dry run|Done'
else
    echo "?? python3 + pyyaml not available; skipped the dry run"
fi
