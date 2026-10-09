# CopperArch Media — Architecture Report

Status snapshot before the "self-contained ISO build" work. Classifies every
component by origin and flags anything that assumes Linux or needs a human.

## 1. What this is

A custom FreeBSD 15.1 distribution: KDE Plasma desktop + a jail-based media
server (Jellyfin/Plex/*arr/qBittorrent), a WireGuard-confined download path with
a pf kill-switch, Nextcloud, a self-healing dashboard, and a native Qt graphical
installer — delivered as a bootable live ISO.

## 2. Pinned FreeBSD source (the real base)

| Field | Value |
|---|---|
| Repository | `https://github.com/freebsd/freebsd-src` (official FreeBSD GitHub mirror) |
| Why the mirror | `git.FreeBSD.org` is blocked by this environment's egress proxy (403); the GitHub mirror is bit-identical and is documented as the fallback |
| Branch | `releng/15.1` |
| Pinned commit | `e38a7085f3a8ecd317c947591fe42b5ca9ab317b` |
| Release tooling used | `release/release.sh`, `release/amd64/mkisoimages.sh`, `usr.sbin/bsdinstall` |
| Verified against source | installerconfig `#!/bin/sh` split + `ZFSBOOT_*` knobs; the scripted-install subcommand order; `mkisoimages.sh` arg signature |

## 3. Component inventory by origin

### FreeBSD-native (correct — keep as-is)
| Component | FreeBSD mechanism |
|---|---|
| `lib/platform.py` | `pkg`, `bastille`, `sysrc`/`service` (rc.d), `pfctl`, kernel `if_wg` |
| `stacks/stack.yaml` | Bastille jail manifest (one jail per service) |
| `vpn/wg0.conf.tmpl`, `pf-killswitch.conf.tmpl` | kernel WireGuard + pf |
| `templates/daily-routine.sh` | `service`, `jls`, `zpool`, `smartctl`, `pkg`, `freebsd-update` |
| `templates/nextcloud/*` | `nextcloud-php83`, PostgreSQL, Caddy, redis |
| `templates/dashboard/*` | collector reads `sysctl`/`jls`/`bastille`; repairs via `service`/`bastille` |
| `installer/configuration/firstboot.sh`, `installerconfig` | `pkg`, `kde`, `sddm`, `bsdinstall` |
| `installer/gui/backend/copperarch-install.sh` | drives `bsdinstall zfsboot/mount/distextract/...` |
| `dist/release.conf`, `overlay/*`, `build-release.sh` | `release.sh` + `extra_chroot_setup()` |

### Cross-platform source, compiled on FreeBSD (keep)
| Component | Note |
|---|---|
| `installer/gui/` (Qt 6: CMake + C++ + QML) | not Linux-specific; builds against `qt6-*` from FreeBSD pkg. No Linux code. |
| `lib/*.py`, `templates/dashboard/*.py` | stdlib Python; runs on FreeBSD `python312` |

### Borrowed from Fedora / Bazzite / Linux
| What | Reality |
|---|---|
| Anaconda / Bazzite installer | **Concept only, zero code.** Anaconda is Linux-bound (rpm/ostree/blivet/systemd) and cannot run on FreeBSD. The Calamares/Anaconda *flow* is reimplemented natively in Qt (`installer/gui`). Nothing Linux is shipped or executed. |
| Immich (photo stack) | Dropped (no FreeBSD build); replaced by native Nextcloud Photos/Memories. |

### Linux-assuming leftovers
None in runtime code. The strings `docker`/`apt`/`systemd` that remain are:
(a) the dashboard JSON key `docker` (holds **jail** data; kept only so
`index.html` renders unchanged), and (b) comments describing the Linux edition
this was ported from. No Linux binary or syscall is invoked anywhere.

## 4. What currently needs a human (and the plan to remove it)

| Manual step today | Resolution |
|---|---|
| "Run `build-release.sh` on a FreeBSD host" | **Self-contained builder**: CI (FreeBSD VM) + a local `build.sh` that auto-provisions an ephemeral FreeBSD build VM via QEMU. The user runs one command / clicks one button; no FreeBSD host is set up by hand. |
| `installerconfig` hardcodes `ZFSBOOT_DISKS=ada0` | Interactive path = the Qt installer (auto-detects disks). Unattended path = detect the first real disk at run time. |
| Repo cloned from a GitHub URL at install time | The project is **baked into the image** by `extra_chroot_setup()`, so install needs no network fetch of itself. |
| Secrets (WireGuard keys, passwords) | Inherently user-supplied; `profiles/unattended.yaml` ships with VPN/Nextcloud **off** so first boot is hands-off, and they're enabled later with `./rebuild`. |

## 5. Build pipeline (target state)

```
freebsd-src @ releng/15.1 (pinned e38a7085f3a8)   ← real FreeBSD base
          │
   release.conf  ──►  release.sh  ──►  extra_chroot_setup()
          │                               ├─ pkg: kde6 + qt6 + bastille + python
          │                               ├─ build installer/gui (cmake/ninja)
          │                               ├─ bake the whole project into the image
          │                               └─ lay the live overlay (autologin→installer)
          ▼
   mkisoimages.sh  ──►  CopperArch-Media-15.1-amd64.iso   ← bootable live+install ISO
```

The only thing that isn't "just text in this repo" is the **FreeBSD machine that
runs the compile** — and the self-contained builder provisions that itself, so
from the user's side the repo does contain everything required to produce the
ISO.
