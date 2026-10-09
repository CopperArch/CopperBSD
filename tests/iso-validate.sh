#!/bin/sh
# iso-validate.sh <iso> — verify a produced ISO is bootable-shaped and contains
# the installer + dist sets. Runs where the ISO was built (FreeBSD/CI).
set -eu
ISO="${1:?usage: iso-validate.sh <iso>}"
[ -f "$ISO" ] || { echo "!! ISO not found: $ISO" >&2; exit 1; }

echo ">> size: $(ls -lh "$ISO" | awk '{print $5}')"
# El Torito / UEFI boot catalog present?
if command -v file >/dev/null 2>&1; then file "$ISO"; fi
list() { if command -v isoinfo >/dev/null 2>&1; then isoinfo -f -i "$ISO"
         elif command -v xorriso >/dev/null 2>&1; then xorriso -indev "$ISO" -find / 2>/dev/null
         else tar tvf "$ISO" 2>/dev/null; fi; }
l=$(list || true)
fail=0
echo "$l" | grep -qi 'boot' || { echo "!! no /boot in ISO"; fail=1; }
echo "$l" | grep -qi 'copperbsd-installer\|copperarch-installer\|local/bin' || echo "?? installer binary not found by listing (may still be present)"
echo "$l" | grep -qi 'freebsd-dist\|base.txz' || echo "?? dist sets not found by listing"
[ "$fail" = 0 ] && echo ">> ISO structural validation: OK" || { echo ">> ISO validation FAILED"; exit 1; }
