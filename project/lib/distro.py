"""CopperBSD's changes to the upstream install steps.

project/ is a copy of freebsd-media-setup (see tools/sync-project.sh); this is
the one Python file in it that is CopperBSD's own. Upstream's lib/steps.py
calls adjust_order() when this file exists, so everything CopperBSD does
differently is here and nowhere else:

  * no browser dashboard page, KDE panel/Konsole theming or local AI model --
    CopperBSD has a native dashboard (dashboard/) and its own desktop choices.
    The dashboard step installs only what the native app talks to: the
    collector, the repair server and the terminal bridge behind its dock.
  * no automatic pooling of spare disks -- first boot runs every step
    unattended, and an unattended `zpool create` over whatever second disk a
    desktop machine happens to have is not a decision to make for someone.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

from .render import render_file
from .steps import _exec, retire_old_dashboard_server

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
    what it talks to: the status collector (writes status.json every 10 s),
    the loopback repair server that runs the whitelisted fixes, and ttyd, the
    loopback terminal bridge behind the dashboard's terminal dock, with
    Claude Code to run in it."""
    if not ctx.profile.use_dashboard:
        return True, "dashboard disabled in profile"
    if not accept("Install the dashboard's status collector, repair server "
                  "and terminal dock service?"):
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
        # Terminal dock: ttyd carries the terminal to the dashboard, bash runs
        # dashboard-pane.sh, tmux keeps an agent's job alive when the dock is
        # closed, xclip is what a selection in the dock is copied with; htop
        # and ncdu are the "Processes" and "Disk usage" panes.
        c.sudo.run(["pkg", "install", "-y", "bash", "ttyd", "tmux", "xclip",
                    "htop", "ncdu"],
                   timeout=600, env=dict(os.environ, ASSUME_ALWAYS_YES="YES"))
        # Claude Code, the dock's first pane. FreeBSD packages it as a Linux
        # program: it needs the Linux binary support switched on (the package
        # refuses to install without it) and brings linux_base-rl9 with it.
        # Best effort -- without it the dock still has its system panes, and
        # the picker simply does not list Claude Code.
        claude_note = ""
        if not Path("/usr/local/bin/claude").exists():
            c.sudo.run(["sysrc", "linux_enable=YES"], timeout=30, quiet=True)
            c.sudo.run(["service", "linux", "start"], timeout=60, quiet=True)
            p = c.sudo.run(["pkg", "install", "-y", "claude-code"], timeout=1800,
                           env=dict(os.environ, ASSUME_ALWAYS_YES="YES"), quiet=True)
            if p.returncode != 0:
                claude_note = ("; Claude Code could NOT be installed (pkg install "
                               "claude-code) -- the dock has its other panes")
        # One OpenRouter key powers every online AI pane; the model block
        # under it is kept current by ai-panes-check.py (nightly routine).
        ds = conf / "deepseek.env"
        key = c.profile.openrouter_api_key
        if not ds.exists():
            ds.write_text(
                "# chmod 600. One OpenRouter key powers every online AI pane.\n"
                "# Get one (free tier available) at https://openrouter.ai/keys\n"
                f"DEEPSEEK_API_KEY={key}\n"
                "DEEPSEEK_BASE_URL=https://openrouter.ai/api/v1\n"
                "# The block below is rewritten nightly by ai-panes-check.py.\n")
        elif key:
            ds.write_text(re.sub(r"^DEEPSEEK_API_KEY=.*$", f"DEEPSEEK_API_KEY={key}",
                                 ds.read_text(), count=1, flags=re.M))
        ds.chmod(0o600)
        # ttyd's command line, in a file so cron does not have to quote it.
        # Loopback only, refuses cross-origin WebSockets, at most two clients;
        # the program comes from dashboard-pane.sh's fixed list (--url-arg
        # picks an entry, it cannot pass a command). --signal 9: a pane whose
        # page went away is killed outright. With ttyd's default hang-up, a
        # shell on FreeBSD first waits for its closed terminal to drain and
        # lingers for five minutes (kern.tty_drainwait). An agent pane is
        # unaffected either way: what gets killed is its tmux client, and the
        # session carries on.
        ttyd = bin_dir / "dashboard-ttyd.sh"
        ttyd.write_text(
            "#!/bin/sh\n"
            "# Written by CopperBSD's installer (project/lib/distro.py).\n"
            "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH\n"
            "exec ttyd --port 7682 --interface 127.0.0.1 --writable --check-origin \\\n"
            "    --url-arg --max-clients 2 --signal 9 --client-option fontSize=13 \\\n"
            "    --client-option cursorBlink=true --client-option disableLeaveAlert=true \\\n"
            "    --client-option 'theme={\"background\":\"#0b0f16\"}' \\\n"
            f"    {bin_dir}/dashboard-pane.sh\n")
        ttyd.chmod(0o755)
        # Name of the active VPN for the dashboard's VPN card (the Change VPN
        # provider dialog rewrites it when the config is replaced).
        label = vpn_label(c.profile.vpn_provider, c.profile.wg_endpoint)
        if label:
            (conf / "vpn-name").write_text(label + "\n")
        # Written as root (the installer runs as root); the collector and the
        # dashboard app run as the desktop user and must own all of it.
        c.sudo.run(["chown", "-R", f"{user}:{user}", str(home / ".local"),
                    str(home / ".config")], timeout=60)

        # Model slugs, prices and the free-model list, so the dock's picker is
        # right the first time it is opened. As the desktop user (-l: its own
        # HOME); needs the network, and a failure only means "filled in by
        # tonight's routine".
        c.sudo.run(["su", "-l", user, "-c", f"{bin_dir}/ai-panes-check.py"],
                   timeout=90, quiet=True)

        # Terminal bridge: the DESKTOP USER's crontab, as a watchdog. Whatever
        # runs in the dock runs as that user, never as root.
        ttyd_launch = (f"pgrep -u {user} -x ttyd >/dev/null 2>&1 || "
                       f"/usr/sbin/daemon -r -o {share}/ttyd.log {ttyd}")
        ttyd_ok = c.plat.crontab_user(
            c.sudo, [f"* * * * * {ttyd_launch}  # status-dashboard ttyd watchdog"],
            user, tag="dashboard-ttyd")
        # Restarted, so a changed command line or pane script takes effect now.
        c.sudo.run(["pkill", "-u", user, "-f", "dashboard-ttyd.sh"], quiet=True)
        c.sudo.run(["pkill", "-u", user, "-x", "ttyd"], quiet=True)
        c.sudo.run(["su", "-l", user, "-c",
                    f"({ttyd_launch}) < /dev/null > /dev/null 2>&1 &"], timeout=30)

        # Collector: ROOT's crontab. Everything it reports
        # about a jail comes from `jexec`, which only root may run;
        # DASHBOARD_HOME points it at the desktop user's data directory.
        # (Earlier CopperBSD versions ran it from the user's own crontab.)
        _drop_cron_lines(c, user, ("status-collect.py", "daily-routine.sh"),
                         exact=("# freebsd-media-setup",))
        c.plat.crontab_user(c.sudo, [], user, tag="dashboard-collector")
        collect = (f"env DASHBOARD_HOME={home} python3.12 "
                   f"{bin_dir}/status-collect.py")
        # cron starts it once a minute; --loop has it collect every 10 s for
        # that minute, so the dashboard is never more than seconds behind.
        cron_ok = c.plat.crontab_user(
            c.sudo, [f"* * * * * {collect} --loop 60 10 >/dev/null 2>&1  # status-dashboard collector"],
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
        retire_old_dashboard_server(c)
        c.sudo.run(["sh", "-c", f"({launch}) < /dev/null > /dev/null 2>&1 &"],
                   timeout=30)
        return cron_ok and server_ok and ttyd_ok, (
            "collector + repair server (127.0.0.1:8099) and terminal dock "
            f"service (127.0.0.1:7682) installed{claude_note}; "
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
