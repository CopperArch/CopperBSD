"""FreeBSD platform layer.

The Linux edition of this installer switched between apt/dnf/pacman/zypper.
FreeBSD has exactly one package manager (pkg) and one service manager (rc.d),
so the "family" axis collapses — but two new axes open up that Docker hid on
Linux:

  * containers  -> FreeBSD **jails**, driven by **Bastille** (POSIX sh, zero
                   deps, actively maintained; the 2026 consensus manager).
  * VPN         -> there is no gluetun. A dedicated **WireGuard jail** owns the
                   tunnel and the torrent jail routes through it, with a **pf**
                   kill-switch so a dropped tunnel leaks nothing (see vpn/).

Everything the installer installs on the HOST goes through PKGS; everything it
installs INTO A JAIL goes through JAIL_PKGS + the Bastille helpers below. No
step ever calls pkg / service / bastille / pfctl directly.
"""
from __future__ import annotations

import os
import platform as _platform
import shutil
from dataclasses import dataclass, field

from .util import have, run


@dataclass
class Platform:
    distro_id: str = "freebsd"
    pretty: str = "FreeBSD"
    release: str = ""                      # e.g. 15.1-RELEASE
    arch: str = field(default_factory=lambda: _platform.machine())
    abi: str = ""                          # FreeBSD:15:amd64

    # ── host packages (logical -> pkg origin/name) ───────────────────────
    # Kept as ORIGINS where the plain name is ambiguous; pkg resolves both.
    PKGS = {
        "python3":       "python312",
        "tkinter":       "py312-tkinter",
        "git":           "git",
        "curl":          "curl",
        "jq":            "jq",
        "smartmontools": "smartmontools",
        "htop":          "htop",
        "ncdu":          "ncdu",
        "rsync":         "rsync",
        "unzip":         "unzip",
        # container + network substrate (this is what replaces Docker)
        "bastille":      "bastille",
        "wireguard":     "wireguard-tools",   # kernel if_wg + wg-quick userland
        "caddy":         "caddy",             # reverse proxy, runs on host or jail
        # desktop (KDE Plasma 6 on X11 — the stable session on FreeBSD in 2026)
        "kde":           "kde6",
        "sddm":          "sddm",
        "xorg":          "xorg",
        "drm-kmod":      "drm-kmod",          # GPU / KMS for transcode + desktop
    }

    # ── packages installed INSIDE service jails (logical -> pkg) ─────────
    # These are the FreeBSD-native equivalents of the linuxserver.io images.
    JAIL_PKGS = {
        "plex":       "plexmediaserver-plexpass",   # or plexmediaserver
        "jellyfin":   "jellyfin",
        "sonarr":     "sonarr",
        "radarr":     "radarr",
        "prowlarr":   "prowlarr",
        "bazarr":     "bazarr",
        "qbittorrent":"qbittorrent-nox",
        "jellyseerr": "jellyseerr",                 # falls back to node build if absent
        "caddy":      "caddy",
        "wireguard":  "wireguard-tools",
    }

    # ── rc.d knob + service name per app ─────────────────────────────────
    # rc knob names occasionally differ from the app name (Plex is the classic
    # offender). Centralised here so a wrong guess is a one-line fix, and the
    # installer prints `pkg info -D <pkg>` (the pkg-message) so you can confirm.
    RC = {
        "plex":        ("plexmediaserver_plexpass", "plexmediaserver_plexpass"),
        "jellyfin":    ("jellyfin", "jellyfin"),
        "sonarr":      ("sonarr", "sonarr"),
        "radarr":      ("radarr", "radarr"),
        "prowlarr":    ("prowlarr", "prowlarr"),
        "bazarr":      ("bazarr", "bazarr"),
        "qbittorrent": ("qbittorrent", "qbittorrent"),
        "jellyseerr":  ("jellyseerr", "jellyseerr"),
        "caddy":       ("caddy", "caddy"),
    }

    def pkg_name(self, logical: str) -> str | None:
        return self.PKGS.get(logical)

    def jail_pkg(self, logical: str) -> str | None:
        return self.JAIL_PKGS.get(logical)

    # ── detection ────────────────────────────────────────────────────────
    @staticmethod
    def detect() -> "Platform":
        sysname = _platform.system()
        if sysname != "FreeBSD":
            # Let the caller decide; the installer refuses on non-FreeBSD but we
            # still return a usable object for --dry-run on a dev laptop.
            return Platform(distro_id=sysname.lower(),
                            pretty=f"{sysname} (not FreeBSD — dry-run only)")
        rel = run(["freebsd-version", "-u"], quiet=True)
        abi = run(["pkg", "config", "ABI"], quiet=True)
        return Platform(
            release=(rel.stdout.strip() if rel.returncode == 0 else _platform.release()),
            abi=(abi.stdout.strip() if abi.returncode == 0 else ""),
            pretty=f"FreeBSD {_platform.release()}",
        )

    def is_freebsd(self) -> bool:
        return self.distro_id == "freebsd"

    # ── host package installation ────────────────────────────────────────
    def install(self, sudo, logicals: list[str]) -> tuple[bool, str]:
        names = [self.pkg_name(l) for l in logicals]
        missing = [l for l, n in zip(logicals, names) if n is None]
        if missing:
            return False, "no pkg mapping for: " + ", ".join(missing)
        names = [n for n in names if n]
        # ASSUME_ALWAYS_YES keeps pkg non-interactive; bootstraps pkg if needed.
        p = sudo.run(["pkg", "install", "-y", *names], timeout=3600,
                     env=dict(os.environ, ASSUME_ALWAYS_YES="YES"))
        return p.returncode == 0, f"rc={p.returncode}"

    # ── rc.d service control (host) ──────────────────────────────────────
    def service(self, sudo, knob: str, action: str) -> bool:
        """action: enable | disable | start | stop | restart | status."""
        if action in ("enable", "disable"):
            val = "YES" if action == "enable" else "NO"
            return sudo.run(["sysrc", f"{knob}_enable={val}"],
                            timeout=60).returncode == 0
        # map to `service <name> <action>`; knob doubles as service name here
        return sudo.run(["service", knob, action], timeout=180).returncode == 0

    def sysrc(self, sudo, *assignments: str) -> bool:
        return sudo.run(["sysrc", *assignments], timeout=60).returncode == 0

    # ── Bastille jail helpers (the Docker-compose replacement) ───────────
    def bastille_bootstrapped(self) -> bool:
        p = run(["bastille", "list", "release"], quiet=True)
        return p.returncode == 0 and bool(p.stdout.strip())

    def bastille_bootstrap(self, sudo, release: str) -> bool:
        ok = self.sysrc(sudo, "bastille_enable=YES")
        p = sudo.run(["bastille", "bootstrap", release, "update"], timeout=3600)
        return ok and p.returncode == 0

    def jail_exists(self, name: str) -> bool:
        p = run(["bastille", "list", "-a"], quiet=True)
        return p.returncode == 0 and any(
            line.split() and line.split()[-1] == name or f" {name} " in f" {line} "
            for line in p.stdout.splitlines())

    def jail_create(self, sudo, name: str, release: str, ip: str,
                    interface: str = "") -> bool:
        cmd = ["bastille", "create", name, release, ip]
        if interface:
            cmd += [interface]
        ok = sudo.run(cmd, timeout=1200).returncode == 0
        if ok:
            self._jail_allow_mlock(sudo, name)
        return ok

    def _jail_allow_mlock(self, sudo, name: str) -> None:
        """Let the jail call mlock(2). The .NET runtime (Jellyfin, Prowlarr,
        Sonarr/Radarr...) calls it while starting; without allow.mlock the CLR
        dies with "Failed to create CoreCLR, HRESULT: 0x8007FF02" and the
        service crash-loops. Bastille does not set it by default."""
        conf = f"/usr/local/bastille/jails/{name}/jail.conf"
        sudo.run(["sh", "-c",
                  f"grep -q 'allow.mlock' {conf} || "
                  f"sed -i '' 's/^\\(  *enforce_statfs = [0-9];\\)$/\\1\\n  allow.mlock;/' {conf}"],
                 timeout=30)
        # allow.* only applies to a (re)started jail
        sudo.run(["bastille", "restart", name], timeout=180)

    def jail_pkg_install(self, sudo, name: str, pkgs: list[str]) -> bool:
        p = sudo.run(["bastille", "pkg", name, "install", "-y", *pkgs],
                     timeout=3600, env=dict(os.environ, ASSUME_ALWAYS_YES="YES"))
        return p.returncode == 0

    def jail_sysrc(self, sudo, name: str, *assignments: str) -> bool:
        return sudo.run(["bastille", "sysrc", name, *assignments],
                        timeout=60).returncode == 0

    def jail_service(self, sudo, name: str, svc: str, action: str) -> bool:
        return sudo.run(["bastille", "cmd", name, "service", svc, action],
                        timeout=180).returncode == 0

    def jail_mount(self, sudo, name: str, host_path: str, jail_path: str,
                   ro: bool = False) -> bool:
        """nullfs-mount a host dataset into a jail (the compose `volumes:` map).
        Bastille records this in the jail's fstab so it survives restarts."""
        opts = "ro" if ro else "rw"
        return sudo.run(["bastille", "mount", name, host_path, jail_path,
                         "nullfs", opts, "0", "0"], timeout=60).returncode == 0

    # ── pf firewall (replaces ufw/firewalld AND gluetun's kill-switch) ───
    def pf_reload(self, sudo, conf: str = "/etc/pf.conf") -> bool:
        self.sysrc(sudo, "pf_enable=YES")
        # load ruleset then (re)start pf; -f is idempotent
        loaded = sudo.run(["pfctl", "-f", conf], timeout=60).returncode == 0
        sudo.run(["service", "pf", "start"], timeout=60)
        return loaded

    def kldload(self, sudo, *modules: str) -> bool:
        ok = True
        for m in modules:
            # persist across reboot + load now
            self.sysrc(sudo, f'kld_list+={m}')
            if run(["kldstat", "-q", "-n", m], quiet=True).returncode != 0:
                ok = sudo.run(["kldload", m], timeout=60).returncode == 0 and ok
        return ok

    # ── cron (root or user) — identical semantics to the Linux edition ───
    def crontab_user(self, entries: list[str]) -> bool:
        p = run(["crontab", "-l"], quiet=True)
        existing = p.stdout.splitlines() if p.returncode == 0 else []
        marker = "# freebsd-media-setup"
        keep = [l for l in existing if marker not in l
                and not any(l.strip() == e.strip() for e in entries)]
        new = "\n".join(keep + [marker] + entries) + "\n"
        return run(["crontab", "-"], input_text=new, quiet=True).returncode == 0
