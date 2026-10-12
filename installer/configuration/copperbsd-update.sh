#!/bin/sh
#
# copperbsd-update — bring an installed CopperBSD up to the latest version
# published on GitHub. Installed as /usr/local/libexec/copperbsd-update; the
# dashboard's Update button runs it through the repair server (which is root).
#
#   copperbsd-update --check     compare versions; changes nothing, needs no root
#   copperbsd-update             download the latest tree and apply it (root)
#   copperbsd-update --force     apply even when the versions already match
#
# What an update replaces:
#   /usr/local/freebsd-media-setup     the media-server project (templates,
#                                      installer, nightly routine source)
#   /usr/local/share/copperbsd/        desktop package lists, session files and
#                                      the dashboard source — the dashboard app
#                                      is rebuilt when its source changed
#   this script itself
# and then re-applies the media project with the saved profile so new scripts
# and templates actually land. FreeBSD itself and packages are NOT touched
# here — that is `pkg upgrade` / `freebsd-update` (the dashboard's other
# update button).
#
# --check prints three lines the dashboard parses:
#   installed=<version|unknown>
#   latest=<version|unknown>
#   available=<yes|no|unknown>

set -u

REPO="${COPPERBSD_REPO_SLUG:-CopperArch/CopperBSD}"
BRANCH="${COPPERBSD_BRANCH:-main}"
SHARE=/usr/local/share/copperbsd
PROJ=/usr/local/freebsd-media-setup
VFILE="$SHARE/VERSION"
LOG=/var/log/copperbsd-update.log
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH/VERSION"
TARBALL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"

say() { printf '%s\n' "$*"; }

installed_version()
{
    if [ -r "$VFILE" ]; then head -n 1 "$VFILE" | tr -d '[:space:]'; else printf unknown; fi
}

latest_version()
{
    v=$(fetch -T 20 -qo - "$RAW" 2>/dev/null | head -n 1 | tr -d '[:space:]')
    case "$v" in
        [0-9]*.[0-9]*) printf '%s' "$v" ;;
        *)             printf unknown ;;
    esac
}

# yes when $2 is a strictly newer dotted version than $1
is_newer()
{
    [ "$1" = "$2" ] && return 1
    newest=$(printf '%s\n%s\n' "$1" "$2" | sort -t . -k1,1n -k2,2n -k3,3n | tail -n 1)
    [ "$newest" = "$2" ]
}

check()
{
    inst=$(installed_version)
    late=$(latest_version)
    say "installed=$inst"
    say "latest=$late"
    if [ "$late" = unknown ]; then
        say "available=unknown"
    elif [ "$inst" = unknown ] || is_newer "$inst" "$late"; then
        say "available=yes"
    else
        say "available=no"
    fi
}

# Same recipe as first boot (installer/configuration/firstboot.sh): the build
# tools are installed for the build and removed again afterwards.
rebuild_dashboard()
{
    say "rebuilding the dashboard app"
    env ASSUME_ALWAYS_YES=YES pkg install -y cmake ninja pkgconf qt6-base \
        qt6-declarative qt6-svg kf6-kirigami kf6-qqc2-desktop-style kf6-kio \
        kf6-breeze-icons >>"$LOG" 2>&1 \
        || say "WARNING: dashboard build dependencies failed (see $LOG)"
    BLD=/var/tmp/copper-dashboard-build
    rm -rf "$BLD"
    if cmake -S "$SHARE/dashboard" -B "$BLD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_INSTALL_PREFIX=/usr/local >>"$LOG" 2>&1 \
       && cmake --build "$BLD" >>"$LOG" 2>&1 \
       && cmake --install "$BLD" >>"$LOG" 2>&1; then
        say "dashboard rebuilt — close and reopen it to see the new version"
        rc=0
    else
        say "WARNING: the dashboard failed to build; the old one stays in place (see $LOG)"
        rc=1
    fi
    rm -rf "$BLD"
    env ASSUME_ALWAYS_YES=YES pkg delete -y cmake ninja >>"$LOG" 2>&1 || true
    return $rc
}

# Re-run the media project so updated scripts, templates and the nightly
# routine are actually deployed. Prefer the profile the installer itself saved
# (root only; it holds the passwords it generated) over first boot's copy,
# which has none of them.
reapply_project()
{
    PROFILE=/root/.config/freebsd-media-setup/profile-used.yaml
    [ -r "$PROFILE" ] || PROFILE="$SHARE/profile.yaml"
    [ -r "$PROFILE" ] || { say "no saved media profile — skipping the media-stack re-apply"; return 0; }
    say "re-applying the media stack (this can take a few minutes)"
    python3.12 "$PROJ/install.py" --cli --profile "$PROFILE" --yes >>"$LOG" 2>&1
    rc=$?
    [ $rc -eq 0 ] || say "WARNING: the media-stack installer reported errors (see $LOG)"
    return $rc
}

apply()
{
    FORCE="$1"
    [ "$(id -u)" -eq 0 ] || { say "copperbsd-update must run as root (try: doas $0)"; return 1; }
    inst=$(installed_version)
    late=$(latest_version)
    if [ "$late" = unknown ]; then
        say "could not reach GitHub to read the latest version — nothing changed"
        return 1
    fi
    if [ "$FORCE" != yes ] && [ "$inst" != unknown ] && ! is_newer "$inst" "$late"; then
        say "CopperBSD $inst is already the latest version"
        return 0
    fi
    say "updating CopperBSD $inst -> $late"
    printf '\n=== %s  update %s -> %s ===\n' "$(date)" "$inst" "$late" >>"$LOG"

    WORK=$(mktemp -d /var/tmp/copperbsd-update.XXXXXX) || { say "could not create a work directory"; return 1; }
    trap 'rm -rf "$WORK"' EXIT INT TERM
    if ! fetch -T 60 -qo "$WORK/src.tar.gz" "$TARBALL" 2>>"$LOG"; then
        say "download failed — nothing changed"
        return 1
    fi
    if ! tar -xzf "$WORK/src.tar.gz" -C "$WORK" 2>>"$LOG"; then
        say "the download did not unpack — nothing changed"
        return 1
    fi
    SRC=$(find "$WORK" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    # Refuse anything that is not a complete CopperBSD tree before touching
    # the installed one.
    for need in VERSION project/install.py dashboard/CMakeLists.txt \
                installer/configuration/copperbsd-update.sh packages/desktops.conf; do
        [ -e "$SRC/$need" ] || { say "the download is incomplete ($need missing) — nothing changed"; return 1; }
    done

    warn=0
    say "updating the media-server project"
    install -d "$PROJ"
    cp -a "$SRC/project/." "$PROJ/" || warn=1

    say "updating desktop definitions"
    install -d "$SHARE/desktop"
    cp "$SRC/packages/desktops.conf" "$SHARE/" || warn=1
    cp -a "$SRC/installer/configuration/desktop/." "$SHARE/desktop/" 2>/dev/null || true

    dash_changed=yes
    if [ -d "$SHARE/dashboard" ] && diff -rq "$SRC/dashboard" "$SHARE/dashboard" >/dev/null 2>&1; then
        dash_changed=no
    fi
    if [ "$dash_changed" = yes ]; then
        rm -rf "$SHARE/dashboard.new"
        cp -a "$SRC/dashboard" "$SHARE/dashboard.new" \
            && rm -rf "$SHARE/dashboard" && mv "$SHARE/dashboard.new" "$SHARE/dashboard" || warn=1
    fi
    if [ "$dash_changed" = yes ] || ! command -v copper-dashboard >/dev/null 2>&1; then
        rebuild_dashboard || warn=1
    else
        say "dashboard source unchanged — not rebuilding"
    fi

    # Replace this script by rename, never in place: sh is still reading it.
    install -m 555 "$SRC/installer/configuration/copperbsd-update.sh" \
        /usr/local/libexec/copperbsd-update.new \
        && mv -f /usr/local/libexec/copperbsd-update.new /usr/local/libexec/copperbsd-update

    reapply_project || warn=1

    cp "$SRC/VERSION" "$VFILE" && chmod 644 "$VFILE"
    if [ $warn -eq 0 ]; then
        say "CopperBSD is now version $late"
    else
        say "CopperBSD updated to $late with warnings — see $LOG"
    fi
    return $warn
}

main()
{
    case "${1:-}" in
        --check)   check ;;
        --force)   apply yes ;;
        "")        apply no ;;
        -h|--help) sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//' ;;
        *)         say "usage: copperbsd-update [--check|--force]"; return 2 ;;
    esac
}

# Everything above is parsed before anything runs, so replacing the file
# mid-update cannot change the code that is executing.
main "$@"
exit $?
