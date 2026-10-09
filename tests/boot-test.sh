#!/bin/sh
# boot-test.sh <iso> — boot the ISO headless in QEMU (UEFI) and check it reaches
# a graphical/login state. Runs where QEMU + OVMF exist (build env/CI), NOT in
# the Linux authoring sandbox. Best-effort: serial log is scanned for progress.
set -eu
ISO="${1:?usage: boot-test.sh <iso>}"
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "NOT TESTED: qemu absent"; exit 0; }
OVMF="${OVMF:-/usr/share/OVMF/OVMF_CODE.fd}"
LOG=$(mktemp)
ACCEL=""; [ -e /dev/kvm ] && ACCEL="-accel kvm -cpu host"
echo ">> booting $ISO (UEFI, headless, 90s watchdog)"
timeout 120 qemu-system-x86_64 $ACCEL -m 4096 -smp 2 \
    ${OVMF:+-drive if=pflash,format=raw,readonly=on,file="$OVMF"} \
    -cdrom "$ISO" -boot d -display none -serial file:"$LOG" &
qpid=$!
ok=1
for _ in $(seq 1 90); do
    sleep 1
    if grep -qiE 'sddm|plasma|copperbsd installer|login:' "$LOG" 2>/dev/null; then ok=0; break; fi
    kill -0 $qpid 2>/dev/null || break
done
kill $qpid 2>/dev/null || true
echo "---- serial tail ----"; tail -20 "$LOG" 2>/dev/null || true
[ "$ok" = 0 ] && echo ">> BOOT TEST: reached installer/desktop stage" \
             || { echo ">> BOOT TEST: did not observe installer within watchdog (inspect serial log)"; exit 1; }
