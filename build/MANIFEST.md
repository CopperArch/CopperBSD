# CopperBSD build manifest — traceability vs. upstream FreeBSD 15.1

Everything that differs from stock FreeBSD 15.1, so the system stays auditable.

## Base
- FreeBSD `releng/15.1` @ `e38a7085f3a8ecd317c947591fe42b5ca9ab317b`
- Mirror: github.com/freebsd/freebsd-src (git.FreeBSD.org proxy-blocked here)
- Vendored subset: `freebsd/src-pinned/{release,usr.sbin/bsdinstall,libexec/rc}`
- Full tree fetched at that commit by `build/fetch-src.sh`

## Patches to the FreeBSD source
- **None.** CopperBSD changes nothing in the base source tree. All customization
  is additive via `overlays/` and package installation, so upstream stays pristine
  and updating the pin is a clean operation. (`patches/` exists for future use.)

## Added on top of base (all under the live root, not in base source)
| Path in image | From | Purpose |
|---|---|---|
| `/usr/local/freebsd-media-setup/` | `project/` | the media server (installed system runs it) |
| `/usr/local/CopperBSD/` | whole repo | build provenance kept on-image |
| `/usr/local/bin/copperbsd-installer` | `installer/frontend` | graphical installer (Qt) |
| `/usr/local/libexec/copperbsd-install.sh` | `installer/backend` | bsdinstall driver |
| `/usr/local/etc/sddm.conf.d/…`, `/usr/local/etc/xdg/autostart/…` | `overlays/` | live autologin → installer |
| `/etc/copperbsd-live`, `/etc/copperarch-live` | `overlays/` | live marker (install-safety guard) |
| `/etc/fstab` (live) | `in-vm-build.sh` | read-only root + tmpfs writable overlays |

## Packages baked in (binary pkg, latest at build time)
`kde6 sddm xorg drm-kmod qt6-base qt6-declarative qt6-quickcontrols2 cmake ninja
pkgconf git python311 py311-yaml bastille wireguard-tools caddy ttyd bash`
plus the per-service packages the media stack installs into jails at first run
(see `project/stacks/stack.yaml` and `project/lib/platform.py`).

## Installer ↔ FreeBSD integration points (verified against pinned source)
- scripted-install env: `ZFSBOOT_VDEV_TYPE/ZFSBOOT_DISKS/ZFSBOOT_SWAP_SIZE`,
  `DISTRIBUTIONS`, `nonInteractive` — confirmed in `usr.sbin/bsdinstall/scripts/{script,zfsboot,auto}`.
- subcommand order `zfsboot→mount→distextract→bootconfig→config→chroot→entropy→umount`
  — mirrors `usr.sbin/bsdinstall/scripts/script`.
- ISO packing: `release/amd64/mkisoimages.sh -b <label> <out> <root>` — signature confirmed.

## Build configuration
- `build/config.sh` — all knobs (name, version, arch, pin, package set, paths).
- `FROM_SOURCE=1` buildworld from source · `FROM_SOURCE=0` 15.1 release sets.
- ISO: `CopperBSD-15.1-amd64.iso`, label `COPPERBSD`, UEFI+BIOS via mkisoimages.
