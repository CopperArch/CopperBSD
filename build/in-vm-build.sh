#!/bin/sh
# in-vm-build.sh — builds the CopperBSD live ISO. Runs INSIDE a FreeBSD 15.x
# builder (a VM auto-provisioned by build/freebsd-builder.sh, a CI FreeBSD VM,
# or a FreeBSD host). Produces a bootable UEFI+BIOS live ISO whose boot lands in
# the graphical installer, which installs the complete CopperBSD system.
#
# Phases:
#   1  source at pinned commit        (fetch-src.sh)
#   2  base system into LIVE_ROOT      (buildworld|release sets)
#   3  desktop + project packages      (pkg into LIVE_ROOT)
#   4  the graphical installer         (cmake/ninja build of installer/frontend)
#   5  bake the project + overlays
#   6  live-boot configuration         (autologin -> installer, tmpfs overlays)
#   7  dist sets for the installer      (/usr/freebsd-dist)
#   8  pack bootable ISO               (makefs + mkisoimages.sh -b)
#   9  checksum into build/output
#
# Honesty: the maintainer cannot run this in the Linux authoring sandbox (no
# FreeBSD toolchain / KVM / FreeBSD mirror access). It is written to run in the
# real builder and is exercised by build/freebsd-builder.sh and the CI workflow.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/config.sh"
ROOT="$COPPERBSD_ROOT"

: "${FROM_SOURCE:=1}"      # 1 = buildworld from pinned src (faithful, slow)
                          # 0 = fetch 15.1 release sets (same release, fast/CI)
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)

log() { echo ">> [$(date '+%H:%M:%S')] $*"; }
die() { echo "!! $*" >&2; exit 1; }
[ "$(uname -s)" = "FreeBSD" ] || die "in-vm-build.sh must run on FreeBSD (it is \
the in-builder stage; use build.sh on Linux/macOS to provision the builder)."

# Make re-runs idempotent: a prior LIVE_ROOT can contain schg-flagged base
# binaries (login, su, passwd, ...) that tar cannot overwrite blind.
PKG_CACHE="$WORKDIR/pkg-cache"
if [ -d "$LIVE_ROOT" ]; then
    umount "$LIVE_ROOT/dev" 2>/dev/null || true
    chflags -R noschg "$LIVE_ROOT" 2>/dev/null || true
    # keep downloaded packages across rebuilds -- pkg install re-verifies
    # checksums on reuse, so a stale/partial cache is harmless.
    [ -d "$LIVE_ROOT/var/cache/pkg" ] && mv "$LIVE_ROOT/var/cache/pkg" "$PKG_CACHE.new" 2>/dev/null
    rm -rf "$LIVE_ROOT"
    [ -d "$PKG_CACHE.new" ] && mv "$PKG_CACHE.new" "$PKG_CACHE"
fi
mkdir -p "$WORKDIR" "$LIVE_ROOT" "$ROOT/$OUTDIR"
if [ -d "$PKG_CACHE" ]; then
    mkdir -p "$LIVE_ROOT/var/cache/pkg"
    mv "$PKG_CACHE"/* "$LIVE_ROOT/var/cache/pkg/" 2>/dev/null || true
fi

# makefs(8) segfaults on a host with no /etc/localtime (minimal cloud
# images ship without one), so make sure it exists before step 8.
[ -e /etc/localtime ] || cp /usr/share/zoneinfo/UTC /etc/localtime

# ── 1. source at the pinned commit ──────────────────────────────────────────
sh "$HERE/fetch-src.sh"

# Real upstream bug: base makefs(8)'s cd9660 backend segfaults packing a
# directory with heavy short-name collisions (our live root, ~290k files,
# hits this reliably -- see patches/freebsd-base/README.md). Patch + build
# just that utility (and its lib/libnetbsd dependency) from the pinned
# source; everyone else's makefs/mkimg/etdump stay the stock base ones.
log "patching + building a fixed makefs(8) (patches/freebsd-base)"
PATCHED_MAKEFS="$WORKDIR/makefs-patched"
if [ ! -x "$PATCHED_MAKEFS" ]; then
    patch -p1 -N -d "$SRCDIR" < "$ROOT/patches/freebsd-base/makefs-cd9660-collision-overflow.patch"
    ( cd "$SRCDIR/lib/libnetbsd" && make obj >/dev/null && make depend >/dev/null && make )
    ( cd "$SRCDIR/usr.sbin/makefs" && make obj >/dev/null && make depend >/dev/null && make )
    FOUND=$(find /usr/obj -name makefs -type f -path '*usr.sbin/makefs/makefs' 2>/dev/null | head -1)
    [ -n "$FOUND" ] || die "built makefs not found under /usr/obj"
    cp "$FOUND" "$PATCHED_MAKEFS"
fi

# ── 2. base system into LIVE_ROOT ───────────────────────────────────────────
DISTDIR="$WORKDIR/dist"
mkdir -p "$DISTDIR"
if [ "$FROM_SOURCE" = "1" ]; then
    log "buildworld/buildkernel from pinned source (this is the long part)"
    make -C "$SRCDIR" -j"$JOBS" buildworld buildkernel
    log "installworld + distribution into LIVE_ROOT"
    make -C "$SRCDIR" installworld   DESTDIR="$LIVE_ROOT"
    make -C "$SRCDIR" installkernel  DESTDIR="$LIVE_ROOT"
    make -C "$SRCDIR" distribution   DESTDIR="$LIVE_ROOT"
    log "packaging base.txz/kernel.txz for the installer to extract onto targets"
    ( cd "$LIVE_ROOT" && tar --exclude ./usr/freebsd-dist -cJf "$DISTDIR/base.txz" \
        --options xz:compression-level=6 . )
    ( cd "$LIVE_ROOT/boot" && tar -cJf "$DISTDIR/kernel.txz" kernel )
else
    log "fetching FreeBSD ${DISTRO_VERSION}-RELEASE dist sets (FROM_SOURCE=0)"
    base_url="https://download.freebsd.org/releases/${DISTRO_ARCH}/${DISTRO_ARCH}/${DISTRO_VERSION}-RELEASE"
    for set in base.txz kernel.txz; do
        fetch -o "$DISTDIR/$set" "$base_url/$set"
    done
    log "extracting base into LIVE_ROOT"
    tar -xpf "$DISTDIR/base.txz"   -C "$LIVE_ROOT"
    tar -xpf "$DISTDIR/kernel.txz" -C "$LIVE_ROOT"
fi

# resolv.conf + pkg need to work inside the chroot
cp /etc/resolv.conf "$LIVE_ROOT/etc/resolv.conf"

# devfs must be mounted for anything in the chroot that touches /dev/null,
# /dev/random, etc. (pkg-static included) -- unmount on exit either way.
mkdir -p "$LIVE_ROOT/dev"
mount -t devfs devfs "$LIVE_ROOT/dev"
trap 'umount "$LIVE_ROOT/dev" 2>/dev/null || true' EXIT

run_in_live() { chroot "$LIVE_ROOT" /bin/sh -c "$*"; }

# ── 3. live-medium + build-only packages ────────────────────────────────────
log "installing live-medium + build-only packages into the image"
run_in_live "env ASSUME_ALWAYS_YES=YES pkg bootstrap -f"
run_in_live "env ASSUME_ALWAYS_YES=YES pkg install -y $PKG_SET $BUILD_ONLY_PKGS"

# ── 4+5. stage the CopperBSD tree, build the installer, bake the project ─────
log "staging CopperBSD into the image"
mkdir -p "$LIVE_ROOT/usr/local/CopperBSD"
# Not the pinned FreeBSD source, previous ISOs or the builder VM: they are
# gigabytes of build inputs/outputs the live medium never uses.
( cd "$ROOT" && tar -cf - --exclude ./freebsd --exclude ./build/output \
    --exclude ./build/.vm --exclude ./.git . ) | \
    tar -xf - -C "$LIVE_ROOT/usr/local/CopperBSD"
# the media-server project proper (what the installed system runs)
mkdir -p "$LIVE_ROOT/usr/local/freebsd-media-setup"
cp -a "$ROOT/project/." "$LIVE_ROOT/usr/local/freebsd-media-setup/"

log "building the graphical installer (cmake/ninja) inside the image"
run_in_live "cmake -S /usr/local/CopperBSD/installer/frontend -B /tmp/gui -G Ninja \
                -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local && \
             cmake --build /tmp/gui && cmake --install /tmp/gui && rm -rf /tmp/gui"

log "removing build-only packages (not needed at runtime on the live medium)"
run_in_live "env ASSUME_ALWAYS_YES=YES pkg delete -y $BUILD_ONLY_PKGS" || true
run_in_live "pkg autoremove -y" || true
run_in_live "pkg clean -ay" || true

# Nothing past this point needs the chroot, and makefs (step 8) walks the
# whole LIVE_ROOT tree to pack the ISO -- a live devfs mount in that tree
# crashes it (observed: makefs segfaults scanning /dev's device nodes), and
# baking real device nodes into the ISO would be wrong even if it didn't.
umount "$LIVE_ROOT/dev" 2>/dev/null || true

install -m 0755 "$ROOT/installer/backend/copperarch-install.sh" \
    "$LIVE_ROOT/usr/local/libexec/copperbsd-install.sh"
# the GUI calls copperarch-install.sh by name; keep both names
ln -sf copperbsd-install.sh "$LIVE_ROOT/usr/local/libexec/copperarch-install.sh" 2>/dev/null || \
    cp "$LIVE_ROOT/usr/local/libexec/copperbsd-install.sh" \
       "$LIVE_ROOT/usr/local/libexec/copperarch-install.sh"

log "laying live overlays"
cp -a "$ROOT/overlays/." "$LIVE_ROOT/"
# Overlay files carry the build user's uid; everything here must be root-owned
# (doas refuses a doas.conf that anyone else owns, and rc scripts should be root's).
( cd "$ROOT/overlays" && find . -mindepth 1 -print0 | xargs -0 -I{} chown -h root:wheel "$LIVE_ROOT/{}" )
# rc(8) skips rc.d scripts that are not executable and sddm cannot exec a
# session wrapper without +x -- a checkout that lost the modes (it happened)
# boots to a text login instead of the installer. Never trust the checkout.
chmod 555 "$LIVE_ROOT"/usr/local/etc/rc.d/copperarch_* \
          "$LIVE_ROOT"/usr/local/bin/copperarch-installer*

# ── 6. live-boot configuration ──────────────────────────────────────────────
log "configuring the live session (autologin -> installer, writable overlays)"
# Read-only CD root. /tmp and /var become tmpfs via rc's tmpmfs/varmfs
# AUTO (empty at boot -- image contents of /var are NOT kept). We can't use
# /etc/fstab for this:
# mkisoimages.sh overwrites it with just the cd9660 root line, then deletes it.
# The live user is created now (the root is read-only at run time, so pw(8)
# can't create it then); its home dir lives under /var (a tmpfs at boot) and is
# recreated each boot by overlays/usr/local/etc/rc.d/copperarch_liveuser.
pw -R "$LIVE_ROOT" groupshow live >/dev/null 2>&1 || pw -R "$LIVE_ROOT" groupadd live
pw -R "$LIVE_ROOT" usershow live >/dev/null 2>&1 || \
    pw -R "$LIVE_ROOT" useradd -n live -c "CopperArch Live" -d /var/live -m \
        -g live -G wheel,operator,video -s /bin/sh -w none

sysrc -R "$LIVE_ROOT" zfs_enable=YES
sysrc -R "$LIVE_ROOT" dbus_enable=YES
sysrc -R "$LIVE_ROOT" seatd_enable=YES
sysrc -R "$LIVE_ROOT" sddm_enable=YES
sysrc -R "$LIVE_ROOT" moused_enable=YES
sysrc -R "$LIVE_ROOT" ifconfig_DEFAULT=DHCP
sysrc -R "$LIVE_ROOT" kld_list="amdgpu i915kms"
# login prompt on the first serial port (matches loader.conf's comconsole)
sed -i '' 's|^ttyu0.*|ttyu0\t"/usr/libexec/getty 3wire"\tvt100\tonifconsole,secure|' "$LIVE_ROOT/etc/ttys"
# live marker (the installer refuses to write disks unless this is present)
: > "$LIVE_ROOT/etc/copperbsd-live"
: > "$LIVE_ROOT/etc/copperarch-live"

# ── 7. dist sets the installer extracts onto the target ─────────────────────
mkdir -p "$LIVE_ROOT/usr/freebsd-dist"
cp "$DISTDIR/base.txz" "$DISTDIR/kernel.txz" "$LIVE_ROOT/usr/freebsd-dist/" 2>/dev/null || \
    log "NOTE: dist sets not staged (FROM_SOURCE=0 fetch failed?) — installer will fetch them"

# clean the build-only resolv.conf so it isn't shipped
: > "$LIVE_ROOT/etc/resolv.conf"

# ── 8. pack the bootable ISO (verified mkisoimages.sh signature) ────────────
log "packing bootable ISO"
MKISO="$SRCDIR/release/$DISTRO_ARCH/mkisoimages.sh"
[ -f "$MKISO" ] || die "mkisoimages.sh not found at $MKISO (source incomplete)"
OUT="$ROOT/$OUTDIR/$ISO_NAME"
# -b => bootable (UEFI ESP + BIOS cdboot, handled by mkisoimages.sh for amd64)
# MAKEFS: our patched build (see step-1 comment); MKIMG/ETDUMP: stock base.
MAKEFS="$PATCHED_MAKEFS" sh "$MKISO" -b "$ISO_LABEL" "$OUT" "$LIVE_ROOT"

# ── 9. checksum ─────────────────────────────────────────────────────────────
( cd "$ROOT/$OUTDIR" && sha256 "$ISO_NAME" > "$ISO_NAME.sha256" 2>/dev/null \
    || sha256sum "$ISO_NAME" > "$ISO_NAME.sha256" )
log "DONE -> $OUT"
cat "$ROOT/$OUTDIR/$ISO_NAME.sha256"
