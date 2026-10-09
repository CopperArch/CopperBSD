#!/bin/sh
# build-iso.sh — bake an unattended KDE media-server install ISO.
#
# In the spirit of CopperArch BSD's build-iso.sh: take the official FreeBSD
# release image and inject our installerconfig so booting it installs the base
# OS onto ZFS and then builds KDE + the Bastille stack on first boot — no
# interactive prompts.
#
# MUST run on a FreeBSD host (uses cd9660 mount + makefs/mkisoimages from base).
#
#   ./build-iso.sh                 # fetch + build for the running release
#   ./build-iso.sh 15.1-RELEASE    # explicit release
set -eu

REL="${1:-$(freebsd-version -u | sed 's/-p[0-9]*//')}"
ARCH="$(uname -m)"
BASE="FreeBSD-${REL}-${ARCH}-disc1.iso"
URL="https://download.freebsd.org/releases/${ARCH}/${REL}/${BASE}"
WORK="$(mktemp -d /tmp/copperarch-iso.XXXXXX)"
OUT="CopperArch-Media-${REL}-${ARCH}.iso"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo ">> release=$REL arch=$ARCH work=$WORK"

[ -f "$BASE" ] || { echo ">> fetching $URL"; fetch -o "$BASE" "$URL"; }

echo ">> unpacking official ISO"
MNT="$WORK/mnt"; ROOT="$WORK/root"
mkdir -p "$MNT" "$ROOT"
MD=$(mdconfig -a -t vnode -f "$BASE")
mount -t cd9660 "/dev/$MD" "$MNT"
cp -a "$MNT"/ "$ROOT"/
umount "$MNT"; mdconfig -d -u "$MD"

echo ">> injecting installerconfig (unattended) + repo copy"
chmod -R u+w "$ROOT"
cp "$HERE/bootstrap/installerconfig" "$ROOT/etc/installerconfig"
# ship the repo on the media so first boot doesn't depend on cloning
mkdir -p "$ROOT/usr/local/freebsd-media-setup"
cp -a "$HERE"/ "$ROOT/usr/local/freebsd-media-setup"/

echo ">> repacking bootable ISO -> $OUT"
# mkisoimages.sh ships in /usr/src/release; makefs is the src-free fallback.
if [ -x /usr/src/release/"${ARCH}"/mkisoimages.sh ]; then
    sh /usr/src/release/"${ARCH}"/mkisoimages.sh -b COPPERARCH "$OUT" "$ROOT"
else
    makefs -t cd9660 -o rockridge,label=COPPERARCH,bootimage="i386;$ROOT/boot/cdboot" \
        -o no-emul-boot "$OUT" "$ROOT"
fi

echo ">> done: $OUT"
echo ">> write it: dd if=$OUT of=/dev/daX bs=1m   (or use it in a VM)"
rm -rf "$WORK"
