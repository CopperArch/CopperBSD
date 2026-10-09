# Niri — FreeBSD patch tracking

| field | value |
|---|---|
| upstream | https://github.com/YaLTeR/niri |
| FreeBSD port | x11-wm/niri **26.04_6** (updated 2026-09-08, commit 7316461, maint lme@FreeBSD.org) |
| status on FreeBSD 15.1 amd64 | packaged upstream; the port carries any FreeBSD-specific build glue |
| patches applied by CopperBSD | **none** |
| reason | the official port already builds niri on FreeBSD (Rust + wayland + seatd + libudev-devd). We pin and consume the port rather than inventing patches. |
| what we add instead | session wrapper (`niri-session`), system `config.kdl`, QuickShell autostart, seatd/dbus rc knobs — all additive, outside niri's source |

If a FreeBSD build/runtime defect is found during `tests/desktop-build-test.sh`
or boot testing, a patch goes here documented as: patch-name / reason /
affected version / upstream issue / submitted upstream? / temporary or permanent.
