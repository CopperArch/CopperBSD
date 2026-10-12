"""CopperBSD's changes to the upstream install steps.

project/ is a copy of freebsd-media-setup (see tools/sync-project.sh); this is
the one Python file in it that is CopperBSD's own. Upstream's lib/steps.py
calls adjust_order() when this file exists, so everything CopperBSD does
differently is here and nowhere else:

  * no browser dashboard, KDE panel/Konsole theming or local-AI panes --
    CopperBSD has a native dashboard (dashboard/) and its own desktop choices.
    The dashboard step installs only what the native app talks to.
  * no automatic pooling of spare disks -- first boot runs every step
    unattended, and an unattended `zpool create` over whatever second disk a
    desktop machine happens to have is not a decision to make for someone.
"""
from __future__ import annotations

from pathlib import Path

from .render import render_file
from .steps import _exec

# upstream step title -> dropped
DROP = {"Desktop panel defaults", "Konsole theme", "Local AI (GLM)"}


# ── host packages (no tkinter / browser: there is no web dashboard) ─────────
def install_host_packages(ctx, accept) -> tuple[bool, str]:
    need = ["python3", "git", "curl", "jq", "bastille"]
    if ctx.profile.use_daily_routine:
        need += ["smartmontools", "rsync"]
    if ctx.profile.use_vpn_stack:
        need += ["wireguard"]
    names = [ctx.plat.pkg_name(n) for n in need]
    if not accept("Install host packages?\n  " + ", ".join(names)):
        return False, "declined"
    return _exec(ctx, "host pkg install", lambda c: c.plat.install(c.sudo, need))


# ── media storage (a place for the library; never touches other disks) ──────
def prepare_storage(ctx, accept) -> tuple[bool, str]:
    pool = ctx.profile.media_pool or "/mnt/storage"
    ctx.profile.media_pool = pool
    if not accept(f"Use {pool} for the media library (created if missing)?"):
        return False, "declined"
    def do(c):
        if Path(pool).is_dir():
            note = f"{pool} already exists"
        else:
            note = f"created directory {pool}"
            if c.plat.root_is_zfs() and not c.plat.zfs_dataset_exists("zroot/media"):
                # its own dataset, so the library can be snapshotted and
                # sized apart from the system
                if c.plat.zfs_create_dataset(c.sudo, "zroot/media", pool):
                    note = f"zroot/media dataset mounted at {pool}"
            if not Path(pool).is_dir():
                if c.sudo.run(["mkdir", "-p", pool], timeout=30).returncode != 0:
                    return False, f"could not create {pool}"
        # The Plex jail also mounts the Nextcloud data path (read-only). With
        # Nextcloud off nothing else creates it, and a mount of a path that
        # does not exist fails the whole jail step.
        nc = c.v["NEXTCLOUD_DATA"]
        if not Path(nc).is_dir():
            c.sudo.run(["mkdir", "-p", nc], timeout=30)
        return True, note
    return _exec(ctx, "prepare media storage", do)


# ── dashboard backend (collector + repair server for the native app) ────────
def _drop_cron_lines(c, user: str, needles: tuple[str, ...],
                     exact: tuple[str, ...] = ()) -> None:
    """Remove untagged entries an earlier CopperBSD wrote, so re-applying
    after an update does not leave the old and the new job side by side."""
    p = c.sudo.run(["crontab", "-u", user, "-l"], quiet=True)
    if p.returncode != 0:
        return
    old = p.stdout.splitlines()
    new = [l for l in old if l.strip() not in exact
           and not any(n in l for n in needles)]
    if new == old:
        return
    tmp = Path(f"/tmp/.crontab-legacy-{user}")
    tmp.write_text("\n".join(new).strip("\n") + "\n")
    try:
        c.sudo.run(["crontab", "-u", user, str(tmp)], quiet=True)
    finally:
        tmp.unlink(missing_ok=True)


def install_dashboard_backend(ctx, accept) -> tuple[bool, str]:
    """CopperBSD's dashboard is the native copper-dashboard app; this installs
    what it talks to: the status collector (writes status.json every minute)
    and the loopback repair server that runs the whitelisted fixes."""
    if not ctx.profile.use_dashboard:
        return True, "dashboard disabled in profile"
    if not accept("Install the dashboard's status collector and repair server?"):
        return False, "declined"
    def do(c):
        from .profile import vpn_label
        user = c.profile.user
        home = Path(c.v["HOME"])
        src = c.tpl / "dashboard"
        bin_dir = home / ".local/bin"
        share = home / ".local/share/status-dashboard"
        conf = home / ".config/status-dashboard"
        for d in (bin_dir, share, conf):
            d.mkdir(parents=True, exist_ok=True)

        # Scripts + python modules -> ~/.local/bin, rendering {{MEDIA_POOL}} etc.
        for f in sorted(src.iterdir()):
            if f.suffix in (".py", ".sh"):
                render_file(f, bin_dir / f.name, c.v, mode=0o755)

        # Seed config: API keys (blank, chmod 600) + the VPN-confined group,
        # kept in sync with stack.yaml so collector and repair server agree.
        keys = conf / "media-keys.env"
        if not keys.exists():
            keys.write_text(
                "# chmod 600. Fill these from each app's Settings → General → "
                "Security (API key) and qBittorrent WebUI creds.\n"
                f"QBIT_USER={c.profile.qbit_user}\nQBIT_PASS={c.profile.qbit_password}\n"
                "RADARR_KEY=\nSONARR_KEY=\nPROWLARR_KEY=\nJELLYFIN_KEY=\n")
            keys.chmod(0o600)
        grp = conf / "vpn-group.json"
        if not grp.exists():
            grp.write_text('{"hub": "vpn", '
                           '"members": ["qbittorrent", "sonarr", "radarr"]}\n')
        # Name of the active VPN for the dashboard's VPN card (the Change VPN
        # provider dialog rewrites it when the config is replaced).
        label = vpn_label(c.profile.vpn_provider, c.profile.wg_endpoint)
        if label:
            (conf / "vpn-name").write_text(label + "\n")
        # Written as root (the installer runs as root); the collector and the
        # dashboard app run as the desktop user and must own all of it.
        c.sudo.run(["chown", "-R", f"{user}:{user}", str(home / ".local"),
                    str(home / ".config")], timeout=60)

        # Collector: ROOT's crontab, once a minute. Everything it reports
        # about a jail comes from `bastille cmd`, which only root may run;
        # DASHBOARD_HOME points it at the desktop user's data directory.
        # (Earlier CopperBSD versions ran it from the user's own crontab.)
        _drop_cron_lines(c, user, ("status-collect.py", "daily-routine.sh"),
                         exact=("# freebsd-media-setup",))
        c.plat.crontab_user(c.sudo, [], user, tag="dashboard-collector")
        collect = (f"env DASHBOARD_HOME={home} python3.12 "
                   f"{bin_dir}/status-collect.py")
        cron_ok = c.plat.crontab_user(
            c.sudo, [f"* * * * * {collect} >/dev/null 2>&1  # status-dashboard collector"],
            "root", tag="dashboard-collector")
        c.sudo.run(["sh", "-c", f"({collect}) < /dev/null > /dev/null 2>&1 &"],
                   timeout=30)

        # Repair server: ROOT's crontab, as a watchdog. Its whitelisted fixes
        # restart jails, upgrade packages and update CopperBSD itself, none of
        # which the desktop user can do. DASHBOARD_HOME tells it whose data
        # directory to serve (as root, Path.home() would be /root).
        _drop_cron_lines(c, "root", ("copper-dashboard server watchdog",))
        launch = (f"pgrep -f status-dashboard-server.py >/dev/null 2>&1 || "
                  f"env DASHBOARD_HOME={home} /usr/sbin/daemon -r -o {share}/server.log "
                  f"python3.12 {bin_dir}/status-dashboard-server.py")
        server_ok = c.plat.crontab_user(
            c.sudo, [f"* * * * * {launch}  # status-dashboard server watchdog"],
            "root", tag="dashboard-watchdog")
        # Backgrounded and fully redirected: daemon(8) does not always detach
        # from the invoking shell before returning, and a still-open pipe back
        # to this process would hang the install.
        c.sudo.run(["sh", "-c", f"({launch}) < /dev/null > /dev/null 2>&1 &"],
                   timeout=30)
        return cron_ok and server_ok, (
            "collector + repair server installed (127.0.0.1:8099); "
            "fill API keys in ~/.config/status-dashboard/media-keys.env")
    return _exec(ctx, "install dashboard backend", do)


# upstream step title -> (title, step) used instead
REPLACE = {
    "Host packages":        ("Host packages",     install_host_packages),
    "Storage auto-pooling": ("Media storage",     prepare_storage),
    "Desktop dashboard":    ("Dashboard backend", install_dashboard_backend),
}


def adjust_order(order):
    """Called by upstream's lib/steps.py with its ORDER; returns CopperBSD's."""
    titles = {title for title, _ in order}
    gone = sorted((DROP | set(REPLACE)) - titles)
    if gone:
        # Upstream renamed or removed a step this file changes. Fail here, at
        # sync time, rather than silently running the upstream step instead.
        raise RuntimeError("lib/distro.py is out of date with lib/steps.py: "
                           "no step named " + ", ".join(gone))
    return [REPLACE.get(title, (title, step))
            for title, step in order if title not in DROP]
