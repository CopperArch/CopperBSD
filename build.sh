#!/bin/sh
# build.sh — one command to produce the CopperBSD ISO.
#
#   ./build.sh                 # auto: FreeBSD host → build directly;
#                              #       Linux/macOS → provision a FreeBSD builder VM
#   FROM_SOURCE=1 ./build.sh   # build the base from pinned FreeBSD source (slow, faithful)
#   FROM_SOURCE=0 ./build.sh   # use 15.1 release sets (fast; same pinned release)
#
# Output: build/output/CopperBSD-15.1-amd64.iso (+ .sha256)
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/build/config.sh"

echo "== CopperBSD build =="
echo "   FreeBSD $FREEBSD_BRANCH @ $FREEBSD_COMMIT"
echo "   output: $OUTDIR/$ISO_NAME"
echo

case "$(uname -s)" in
    FreeBSD)
        echo ">> FreeBSD host detected — building directly."
        exec sh "$HERE/build/in-vm-build.sh"
        ;;
    Linux|Darwin)
        if command -v qemu-system-x86_64 >/dev/null 2>&1; then
            echo ">> Non-FreeBSD host — provisioning an ephemeral FreeBSD builder VM."
            exec sh "$HERE/build/freebsd-builder.sh"
        fi
        cat <<EOF
>> Non-FreeBSD host and QEMU is not installed. Two zero-/low-setup options:

   A. CI (no local setup at all): push this repo to GitHub and run the
      "Build CopperBSD ISO" workflow (.github/workflows/build-iso.yml). It
      provisions a FreeBSD VM and uploads the ISO as an artifact.

   B. Local: install QEMU, then re-run ./build.sh —
        Debian/Ubuntu : sudo apt-get install -y qemu-system-x86 genisoimage
        Fedora        : sudo dnf install -y qemu-system-x86 genisoimage
        macOS         : brew install qemu cdrtools

   The build itself is fully automated in both; you do not set up FreeBSD.
EOF
        exit 1
        ;;
    *)
        echo "!! Unsupported host OS: $(uname -s)" >&2
        exit 1
        ;;
esac
