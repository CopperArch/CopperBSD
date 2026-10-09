#!/bin/sh
# freebsd-builder.sh — provision an EPHEMERAL FreeBSD 15.1 builder VM with QEMU
# on a Linux/macOS host, run the CopperBSD build inside it, and copy the ISO
# back out. This is how "./build.sh" produces an ISO without you ever setting up
# a FreeBSD machine by hand (requirement §13).
#
# Requires on the host: qemu-system-x86_64, and network to download.freebsd.org.
# The guest is a FreeBSD cloud image driven by cloud-init; the repo is shared in
# over virtio-9p and the build runs there.
#
# NOT TESTED in the authoring sandbox (no QEMU/KVM/FreeBSD-mirror access there).
# Written to run on a normal Linux/macOS workstation or CI runner with KVM.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/config.sh"
ROOT="$COPPERBSD_ROOT"

QEMU=qemu-system-x86_64
command -v "$QEMU" >/dev/null 2>&1 || {
    cat >&2 <<EOF
!! QEMU not found. Two ways to still get an ISO without a FreeBSD host:
   1. Install QEMU and re-run:  (Debian/Ubuntu) apt-get install qemu-system-x86
                                (Fedora)        dnf install qemu-system-x86
                                (macOS)         brew install qemu
   2. Push to GitHub and run the "Build CopperBSD ISO" Action — it provisions a
      FreeBSD VM in CI and uploads the ISO. Zero local setup.
EOF
    exit 1
}

VMDIR="${VMDIR:-$ROOT/build/.vm}"
mkdir -p "$VMDIR" "$ROOT/$OUTDIR"
IMG_XZ="FreeBSD-${DISTRO_VERSION}-RELEASE-${DISTRO_ARCH}-BASIC-CLOUDINIT-ufs.qcow2.xz"
IMG="$VMDIR/builder.qcow2"
IMG_URL="https://download.freebsd.org/releases/VM-IMAGES/${DISTRO_VERSION}-RELEASE/${DISTRO_ARCH}/Latest/${IMG_XZ}"

# ── 1. base cloud image ─────────────────────────────────────────────────────
if [ ! -f "$IMG" ]; then
    echo ">> downloading FreeBSD ${DISTRO_VERSION} cloud image"
    fetch -o "$VMDIR/$IMG_XZ" "$IMG_URL" 2>/dev/null || curl -fL -o "$VMDIR/$IMG_XZ" "$IMG_URL"
    xz -dk "$VMDIR/$IMG_XZ"
    mv "$VMDIR/${IMG_XZ%.xz}" "$IMG"
    # roomy disk for buildworld + the ISO
    qemu-img resize "$IMG" 80G
fi

# ── 2. cloud-init seed: on boot, mount the shared repo and run the build ─────
SEED="$VMDIR/seed.iso"
mkdir -p "$VMDIR/ci"
cat > "$VMDIR/ci/meta-data" <<EOF
instance-id: copperbsd-builder
local-hostname: copperbsd-builder
EOF
cat > "$VMDIR/ci/user-data" <<EOF
#cloud-config
package_update: true
packages: [git]
runcmd:
  - [ sh, -c, "kldload p9fs || true" ]
  - [ sh, -c, "mkdir -p /mnt/copperbsd && mount -t p9fs -o trans=virtio copperbsd /mnt/copperbsd" ]
  - [ sh, -c, "cd /mnt/copperbsd && env FROM_SOURCE=${FROM_SOURCE:-0} COPPERBSD_OUTDIR=/mnt/copperbsd/${OUTDIR} sh build/in-vm-build.sh > /mnt/copperbsd/build/output/build.log 2>&1; echo \$? > /mnt/copperbsd/build/output/build.rc; poweroff" ]
EOF
# NoCloud seed (genisoimage/xorriso/mkisofs — whichever the host has)
if command -v genisoimage >/dev/null 2>&1; then ISOGEN=genisoimage
elif command -v xorriso   >/dev/null 2>&1; then ISOGEN="xorriso -as mkisofs"
elif command -v mkisofs   >/dev/null 2>&1; then ISOGEN=mkisofs
else echo "!! need genisoimage/xorriso/mkisofs on the host to make the seed ISO" >&2; exit 1; fi
$ISOGEN -output "$SEED" -volid cidata -joliet -rock "$VMDIR/ci/meta-data" "$VMDIR/ci/user-data"

# ── 3. boot the builder (KVM if available), share the repo over 9p ──────────
ACCEL=""; [ -e /dev/kvm ] && ACCEL="-accel kvm -cpu host"
echo ">> booting FreeBSD builder VM (headless); the build runs inside and powers off when done"
"$QEMU" $ACCEL -m "${BUILD_RAM:-8192}" -smp "${BUILD_CPUS:-$(nproc 2>/dev/null || echo 4)}" \
    -drive file="$IMG",if=virtio,format=qcow2 \
    -drive file="$SEED",if=virtio,format=raw,readonly=on \
    -fsdev local,id=repo,path="$ROOT",security_model=none \
    -device virtio-9p-pci,fsdev=repo,mount_tag=copperbsd \
    -netdev user,id=n0 -device virtio-net,netdev=n0 \
    -nographic -serial mon:stdio

# ── 4. collect result ───────────────────────────────────────────────────────
rc=$(cat "$ROOT/$OUTDIR/build.rc" 2>/dev/null || echo 1)
if [ "$rc" = "0" ] && [ -f "$ROOT/$OUTDIR/$ISO_NAME" ]; then
    echo ">> ISO ready: $ROOT/$OUTDIR/$ISO_NAME"
    cat "$ROOT/$OUTDIR/$ISO_NAME.sha256" 2>/dev/null || true
else
    echo "!! build failed inside the VM (rc=$rc). See build/output/build.log" >&2
    exit 1
fi
