# freebsd-base patches

Unlike `patches/niri`, `patches/quickshell`, `patches/mangowc` (empty --
those ports build on FreeBSD unmodified), this directory carries a real,
necessary patch to FreeBSD base.

## makefs-cd9660-collision-overflow.patch

**Real bug, found and fixed while building CopperBSD's live ISO
(2026-10-01), not a theoretical concern.**

`usr.sbin/makefs`'s cd9660 backend crashes with `SIGSEGV` when packing a
directory tree with enough ISO-9660 short-name collisions in one directory
(confirmed via core-dump backtrace: `cd9660_handle_collisions` ->
`cd9660_rename_filename` -> `memcpy`, `cd9660.c:1101`). A CopperBSD live
root (KDE + Qt6 + Xorg, ~293k files) hits this reliably; `isolevel=2` does
not avoid it.

Root cause: `numbts -= delete_chars;` (`cd9660.c:1078`) can go negative when
a directory has enough colliding entries that no unique short name can be
found. The following `memcpy(tmp, iter->o_name, numbts)` passes that
negative `int` as `memcpy`'s unsigned `size_t` length, producing a
multi-exabyte copy that immediately segfaults. The original code's own
comment -- "This code makes a bunch of assumptions. See if you can spot
them all :)" -- flags this function as exactly this kind of unaudited.

Fix: clamp `numbts` to 0 before use. In the pathological case this yields a
degenerate (very short) mangled short name for the colliding entry instead
of crashing; RockRidge (`-o rockridge`, already used by this build) carries
the real long name regardless, so nothing user-visible is lost.

Applied automatically by `build/in-vm-build.sh` against the pinned source
checkout before `usr.sbin/makefs` (and its `lib/libnetbsd` dependency) are
built and used for the ISO-packing step.
