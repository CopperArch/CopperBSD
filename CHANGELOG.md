# Changelog

The project version lives in `VERSION`. It updates by itself: every change
merged to `main` gets the next patch number from
`.github/workflows/bump-version.yml`, which also adds the change to this file.
A change that edits `VERSION` itself (for a bigger jump) is left as it is.

## 0.1.4 - 2026-10-12
- Resync the media project with freebsd-media-setup 0.6.5 (#4)

## 0.1.3 - 2026-10-12
- Fix the ISO validation step failing on good builds (#3)

## 0.1.2 - 2026-10-12
- Dashboard rebuilt to match the Linux edition; update from GitHub; VPN naming (#2)

## 0.1.1 - 2026-10-12
- Rename state dir to ~/.dbmedia (#1)

## 0.1.0 - 2026-10-09
- First published version: FreeBSD 15.1 live ISO build, native Qt 6 graphical
  installer, five selectable desktops (KDE Plasma, GNOME, XFCE, Niri and
  MangoWC with QuickShell), the CopperArch media server baked in, and a native
  Qt dashboard.
