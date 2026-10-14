#!/bin/sh
# iso-validate.sh <iso> — verify a produced ISO is bootable-shaped and contains
# the installer + dist sets. Runs on the FreeBSD builder or on the Linux CI
# runner the ISO is copied back to.
set -eu
ISO="${1:?usage: iso-validate.sh <iso>}"
[ -f "$ISO" ] || { echo "!! ISO not found: $ISO" >&2; exit 1; }

echo ">> size: $(ls -lh "$ISO" | awk '{print $5}')"
# El Torito / UEFI boot catalog present?
if command -v file >/dev/null 2>&1; then file "$ISO"; fi

# Something that can read an ISO 9660 filesystem. FreeBSD's tar is bsdtar and
# can; GNU tar (the Linux runner's) cannot, and used to make this script report
# a good ISO as having no /boot.
if command -v bsdtar >/dev/null 2>&1; then
    LISTER=bsdtar;  list() { bsdtar -tf "$ISO"; }
elif tar --version 2>/dev/null | grep -qi bsdtar; then
    LISTER=tar;     list() { tar -tf "$ISO"; }
elif command -v xorriso >/dev/null 2>&1; then
    LISTER=xorriso; list() { xorriso -indev "$ISO" -find / 2>/dev/null; }
elif command -v isoinfo >/dev/null 2>&1; then
    LISTER=isoinfo; list() { isoinfo -R -f -i "$ISO"; }
elif command -v 7z >/dev/null 2>&1; then
    LISTER=7z;      list() { 7z l -ba "$ISO"; }
else
    echo "!! cannot read the ISO: need bsdtar (libarchive-tools), xorriso, isoinfo or 7z" >&2
    exit 2
fi

# Listed to a file, not a variable piped into grep: `grep -q` stops reading at
# the first match, and the shell then reports a write error for every check.
LIST=$(mktemp "${TMPDIR:-/tmp}/iso-validate.XXXXXX")
trap 'rm -f "$LIST"' EXIT INT TERM
list > "$LIST" || { echo "!! $LISTER could not list the ISO" >&2; exit 1; }
n=$(wc -l < "$LIST" | tr -d ' ')
echo ">> listed $n entries with $LISTER"
[ "$n" -gt 100 ] || { echo "!! only $n entries listed — not a full live image" >&2; exit 1; }

has() { grep -Eqi "$1" "$LIST"; }
fail=0
has '(^|/)boot/loader'        || { echo "!! no /boot/loader in ISO"; fail=1; }
has '(^|/)boot/kernel/kernel' || { echo "!! no kernel in ISO"; fail=1; }
has 'bin/copper(arch|bsd)-installer' || { echo "!! graphical installer not in ISO"; fail=1; }
has 'libexec/copperbsd-install\.sh'  || { echo "!! installer backend not in ISO"; fail=1; }
has 'freebsd-dist/base\.txz' || echo "?? dist sets not in ISO (the installer will fetch them)"
# The live boot depends on these being executable: rc(8) silently skips a
# non-executable rc.d script and sddm cannot start a session wrapper without
# +x -- the ISO then stops at a text login (every CI ISO from 0.1.0 to 0.1.10).
if [ "$LISTER" = bsdtar ] || [ "$LISTER" = tar ]; then
    for f in usr/local/etc/rc.d/copperarch_liveuser usr/local/bin/copperarch-installer-x11-session \
             usr/local/libexec/copperbsd-install.sh; do
        mode=$($LISTER -tvf "$ISO" "$f" "./$f" 2>/dev/null | awk 'NR==1{print $1}')
        case "$mode" in
            -??x*) ;;
            "") echo "!! $f not found in ISO"; fail=1 ;;
            *)  echo "!! $f is not executable in the ISO ($mode)"; fail=1 ;;
        esac
    done
fi
[ "$fail" = 0 ] && echo ">> ISO structural validation: OK" || { echo ">> ISO validation FAILED"; exit 1; }
