#!/bin/sh
# test.sh — run everything testable on THIS host.
#   static checks always; ISO + boot checks if an ISO has been built.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HERE/build/config.sh"

echo "######## STATIC CHECKS (host-agnostic) ########"
sh "$HERE/tests/static-checks.sh"; static=$?

iso="$HERE/$OUTDIR/$ISO_NAME"
if [ -f "$iso" ]; then
    echo; echo "######## ISO VALIDATION ########"
    sh "$HERE/tests/iso-validate.sh" "$iso" || true
    echo; echo "######## BOOT TEST ########"
    sh "$HERE/tests/boot-test.sh" "$iso" || true
else
    echo; echo "(no ISO at $iso yet — run ./build.sh; ISO/boot tests will then run)"
fi
exit $static
