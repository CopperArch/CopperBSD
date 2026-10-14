#!/bin/sh
# ci-boot-test.sh <iso> [timeout-seconds] — boot the live ISO headless (UEFI,
# QEMU) and pass only when the graphical installer is actually running.
#
# The live medium's copperarch_diag service prints the display-stack state
# (processes, sddm.log, Xorg errors) to the first serial port 40/80/140 s after
# boot; this script watches that for the installer process. A structurally
# valid ISO can still stop at a text login (it did, from 0.1.0 to 0.1.10, when
# the live rc.d scripts lost their executable bit) -- only a boot shows that.
#
# Needs qemu-system-x86_64 and OVMF; uses KVM when /dev/kvm is usable.
set -u
ISO="${1:?usage: ci-boot-test.sh <iso> [timeout-seconds]}"
TIMEOUT="${2:-600}"
[ -f "$ISO" ] || { echo "!! ISO not found: $ISO" >&2; exit 1; }

OVMF=""
for f in /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF.fd /usr/share/qemu/OVMF.fd \
         /usr/local/share/edk2-qemu/QEMU_UEFI-x86_64.fd; do
    [ -f "$f" ] && { OVMF=$f; break; }
done
[ -n "$OVMF" ] || { echo "!! no OVMF firmware found" >&2; exit 2; }

ACCEL=tcg
[ -w /dev/kvm ] && ACCEL=kvm
WORK=$(mktemp -d "${TMPDIR:-/tmp}/copper-boot.XXXXXX")
SERIAL="$WORK/serial.log"
echo ">> booting $ISO (accel=$ACCEL, firmware=$OVMF, timeout ${TIMEOUT}s)"
qemu-system-x86_64 -machine q35,accel=$ACCEL -m 4G -smp 2 -bios "$OVMF" \
    -drive file="$ISO",media=cdrom,readonly=on -boot d \
    -netdev user,id=n -device e1000,netdev=n -vga std -usb -device usb-tablet \
    -display none -serial file:"$SERIAL" -monitor none &
QPID=$!
trap 'kill $QPID 2>/dev/null; wait $QPID 2>/dev/null; rm -rf "$WORK"' EXIT INT TERM

result=1; t=0
while [ "$t" -lt "$TIMEOUT" ]; do
    sleep 10; t=$((t + 10))
    kill -0 "$QPID" 2>/dev/null || { echo "!! QEMU exited early"; break; }
    # the serial console writes CRLF line ends
    tr -d '\r' < "$SERIAL" > "$WORK/serial.txt" 2>/dev/null
    if grep -q 'copperarch_diag' "$WORK/serial.txt"; then
        if grep -Eq '/usr/local/bin/copperarch-installer *$' "$WORK/serial.txt"; then
            echo ">> installer running after ~${t}s"; result=0; break
        fi
        # third (last) dump without the installer: it is not coming
        [ "$(grep -c '=== copperarch_diag' "$WORK/serial.txt")" -ge 3 ] && break
    fi
done

echo "---- last serial output ----"
tr -d '\r' < "$SERIAL" | tail -60
if [ "$result" = 0 ]; then
    echo ">> boot test: OK"
else
    echo ">> boot test FAILED: the graphical installer never started"
fi
exit "$result"
