# CopperBSD desktops & Wayland (§ multi-DE extension)

Five sessions, one install, selectable in the installer and at the SDDM greeter.
All Wayland sessions use FreeBSD-native seat management (**seatd**) and **dbus** —
no systemd, no logind.

## Sessions and package groups (real FreeBSD ports, pinned)

| Session | Key packages | Port facts (FreshPorts, 2026-10) |
|---|---|---|
| KDE Plasma | `kde6` + `sddm` | long-established |
| GNOME | `gnome` + GDM/SDDM | long-established |
| XFCE | `xfce` | long-established |
| **Niri + QuickShell** | `niri`, `quickshell`, `xwayland-satellite` | `x11-wm/niri` **26.04_6** (2026-09-08, commit 7316461) |
| **MangoWC + QuickShell** | `mango`, `quickshell` | `x11-wm/mango` **0.17.4** (MangoWC, dwl/wlroots) |

Shared Wayland core: `wayland wayland-protocols seatd libudev-devd mesa-dri
libglvnd xwayland drm-kmod` + utilities (`foot swaybg fuzzel mako swayidle
swaylock wl-clipboard grim slurp wlr-randr pavucontrol-qt`; screen brightness uses FreeBSD's own `backlight(8)`).

Defined in `packages/desktops.conf` (`desktop_pkgs <key>`), installed into the
target by `installer/backend/copperarch-install.sh` during post-install, which
also enables `seatd/dbus/sddm`, lays the session files + Niri `config.kdl` +
QuickShell starter, and sets the user's default session via `.dmrc`.

## FreeBSD-native session startup (no systemd)

- `niri-session` / `mangowc-session` (`/usr/local/bin`) set `XDG_RUNTIME_DIR`,
  run `dbus-run-session`, and launch the compositor.
- QuickShell is started by Niri's own `spawn-at-startup "quickshell"` in
  `/usr/local/etc/niri/config.kdl` — the clean FreeBSD way, not `systemd --user`.
- `seatd_enable=YES` provides seats for wlroots/niri (replaces logind).
- X11 apps under Wayland: `xwayland` + `xwayland-satellite` (niri's model).

## §20 FINAL REPORT — honest status

Authoring happened in a Linux sandbox with **no FreeBSD, no GPU, and FreeBSD
mirrors blocked**. Version/port facts below are **researched (real)**; every
build/runtime/hardware result is **NOT TESTED here** and automated to run in the
FreeBSD builder via `tests/desktop-build-test.sh` + the boot test. Per your rule,
nothing is claimed working that wasn't executed.

```
Niri upstream version:        niri 26.04 series (port 26.04_6)
FreeBSD port version:         x11-wm/niri 26.04_6  (commit 7316461, 2026-09-08)
FreeBSD 15.1 compatibility:   port packaged for FreeBSD:15:amd64 (RESEARCHED)
Build result:                 NOT TESTED HERE — automated (pkg install -n + install)
Runtime result:              NOT TESTED HERE — needs FreeBSD+GPU; automated in boot test
Wayland result:              NOT TESTED HERE
Xwayland result:             NOT TESTED HERE (xwayland pkg in core group)
xwayland-satellite result:   NOT TESTED HERE (in niri group)
QuickShell result:           NOT TESTED HERE — x11/quickshell, upstream FreeBSD support (RESEARCHED); starter shell.qml ships
Intel result:                NOT TESTED — drm-kmod / i915kms auto-loaded by firstboot
AMD result:                  NOT TESTED — amdgpu auto-loaded by firstboot
NVIDIA result:               NOT TESTED — nvidia-drm is the rough edge on FreeBSD; documented, not claimed
Multi-monitor result:        NOT TESTED — niri auto-detects outputs; no hardcoded monitors
Login-manager result:        SDDM greeter lists all installed sessions (config shipped); NOT runtime-tested
Installer result:            Desktop page added to the Qt wizard; static-validated; NOT runtime-tested
VM installation result:      NOT TESTED HERE — run ./build.sh then tests (builder/CI)
```

Patches: **none applied** — the real ports already build these on FreeBSD, so we
pin and consume them (see `patches/*/freebsd/README.md`). The patch dirs exist,
documented, for any defect found during builder/CI testing.

Acceptance criterion (a working FreeBSD 15.1 + Niri + QuickShell session) is
reached by running `./build.sh` and `./test.sh` in a FreeBSD-capable environment
(CI is the zero-setup path); the automation to prove it is in the repo.
