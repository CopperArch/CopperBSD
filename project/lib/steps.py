"""Install steps, in order — FreeBSD edition.

Same contract as the Linux edition: each step takes (ctx, accept) and returns
(ok, summary); nothing that changes the system runs without an explicit accept.
The difference is entirely in the substrate — pkg/bastille/rc.d/pf instead of
apt-dnf-pacman/docker/systemd/ufw.
"""
from __future__ import annotations

import os
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

from .platform import Platform
from .profile import Profile
from .render import render_text, render_file, MissingVar
from .util import have, log, run


class Ctx:
    def __init__(self, profile: Profile, plat: Platform, sudo, dry_run=False,
                 repo_root: Path | None = None):
        self.profile = profile
        self.plat = plat
        self.sudo = sudo
        self.dry_run = dry_run
        self.repo = repo_root or Path(__file__).resolve().parent.parent
        self.tpl = self.repo / "templates"

    @property
    def v(self) -> dict:
        return self.profile.render_vars()

    def stack(self) -> dict:
        raw = (self.repo / "stacks" / "stack.yaml").read_text()
        # render {{SUBNET}} etc. before parsing so the manifest is concrete
        rendered = render_text(raw, self._stack_vars(), "stack.yaml")
        return yaml.safe_load(rendered)

    def _stack_vars(self) -> dict:
        d = dict(self.v)
        d.setdefault("SUBNET", "10.17.0")
        return d


def _exec(ctx: Ctx, desc, fn):
    if ctx.dry_run:
        log(f"  [DRY] {desc}")
        return True, "dry-run"
    try:
        return fn(ctx)
    except Exception as e:  # noqa: BLE001
        return False, f"{desc} failed: {e}"


# ── 0. guardrail ────────────────────────────────────────────────────────────
def check_freebsd(ctx: Ctx, accept) -> tuple[bool, str]:
    if not ctx.plat.is_freebsd() and not ctx.dry_run:
        return False, ("this installer targets FreeBSD; run --dry-run to preview "
                       "on another OS")
    return True, f"{ctx.plat.pretty} (release {ctx.plat.release or '?'})"


# ── 1. host packages ─────────────────────────────────────────────────────────
def install_host_packages(ctx: Ctx, accept) -> tuple[bool, str]:
    need = ["python3", "git", "curl", "jq", "bastille"]
    if ctx.profile.use_daily_routine:
        need += ["smartmontools", "rsync"]
    if ctx.profile.use_dashboard:
        need += ["tkinter"]
    if ctx.profile.use_vpn_stack:
        need += ["wireguard"]
    names = [ctx.plat.pkg_name(n) for n in need]
    if not accept("Install host packages?\n  " + ", ".join(names)):
        return False, "declined"
    return _exec(ctx, "host pkg install", lambda c: c.plat.install(c.sudo, need))


# ── 2. Bastille substrate ────────────────────────────────────────────────────
def bootstrap_bastille(ctx: Ctx, accept) -> tuple[bool, str]:
    rel = ctx.stack().get("release", "15.1-RELEASE")
    if not accept(f"Bootstrap Bastille release {rel} (downloads a base)?"):
        return False, "declined"
    def do(c):
        if c.plat.bastille_bootstrapped():
            return True, "already bootstrapped"
        ok = c.plat.bastille_bootstrap(c.sudo, rel)
        return ok, f"bootstrap {rel} rc={'0' if ok else 'nonzero'}"
    return _exec(ctx, "bastille bootstrap", do)


# ── 3. media jails (no VPN) ──────────────────────────────────────────────────
def create_media_jails(ctx: Ctx, accept) -> tuple[bool, str]:
    if not ctx.profile.use_media_stack:
        return True, "media stack disabled in profile"
    st = ctx.stack()
    rel = st["release"]
    jails = st["jails"]
    if not ctx.profile.use_nextcloud:
        jails = [j for j in jails if j["name"] not in ("nextcloud", "nextcloud-db")]
    listing = ", ".join(j["name"] for j in jails)
    if not accept(f"Create media jails: {listing}?"):
        return False, "declined"
    def do(c):
        made = []
        for j in jails:
            if c.plat.jail_exists(j["name"]):
                made.append(j["name"] + "(exists)"); continue
            c.plat.jail_create(c.sudo, j["name"], rel, j["ip"],
                               f"{st['bridge']}")
            c.plat.jail_pkg_install(c.sudo, j["name"], j["pkg"])
            for k, val in (j.get("rc") or {}).items():
                c.plat.jail_sysrc(c.sudo, j["name"], f"{k}={val}")
            for m in (j.get("mounts") or []):
                c.plat.jail_mount(c.sudo, j["name"], m["host"], m["jail"],
                                  ro=m.get("ro", False))
            for svc in (j.get("services") or []):
                c.plat.jail_service(c.sudo, j["name"], svc, "start")
            made.append(j["name"])
        return True, "jails: " + ", ".join(made)
    return _exec(ctx, "create media jails", do)


# ── 3b. Nextcloud (Immich replacement: photos + files) ──────────────────────
def create_nextcloud_stack(ctx: Ctx, accept) -> tuple[bool, str]:
    if not ctx.profile.use_nextcloud:
        return True, "nextcloud disabled in profile"
    if not accept("Provision Nextcloud (photos/files) — config + occ install "
                  "+ Photos/Memories apps?"):
        return False, "declined"

    def do(c):
        import tempfile
        app_root = "/usr/local/bastille/jails/nextcloud/root"
        # 1. in-jail Caddy vhost + PHP tuning
        render_file(c.repo / "templates/nextcloud/Caddyfile.tmpl",
                    Path(f"{app_root}/usr/local/etc/caddy/Caddyfile"),
                    c.v, mode=0o644)
        render_file(c.repo / "templates/nextcloud/php.ini.tmpl",
                    Path(f"{app_root}/usr/local/etc/php/nextcloud.ini"),
                    c.v, mode=0o644)
        # 2. front reverse-proxy vhost (only if a public domain is set)
        if c.profile.nextcloud_domain:
            front = Path("/usr/local/bastille/jails/caddy/root/usr/local/etc/caddy/Caddyfile")
            snippet = render_text(
                (c.repo / "templates/nextcloud/front-caddy.snippet.tmpl").read_text(),
                c.v, "front-caddy")
            if front.exists() and snippet.strip() not in front.read_text():
                with front.open("a") as fh:
                    fh.write("\n" + snippet + "\n")
            c.plat.jail_service(c.sudo, "caddy", "caddy", "reload")
        # 3. render the bring-up script (carries secrets) to a 600 temp, run, wipe
        fd, tmp = tempfile.mkstemp(suffix="-install-nextcloud.sh")
        os.close(fd)
        tmp_path = Path(tmp)
        try:
            render_file(c.repo / "templates/nextcloud/install-nextcloud.sh",
                        tmp_path, c.v, mode=0o700)
            rc = c.sudo.run(["sh", str(tmp_path)], timeout=1800)
        finally:
            try:
                tmp_path.unlink()
            except OSError:
                pass
        # 4. restart the app jail's services now that config is in place
        for svc in ("redis", "php-fpm", "caddy"):
            c.plat.jail_service(c.sudo, "nextcloud", svc, "restart")
        return rc.returncode == 0, (
            "nextcloud provisioned (admin user "
            f"'{c.profile.nc_admin_user}'); photos/memories installed; "
            f"reach it at {c.profile.nextcloud_domain or c.v['NC_JAIL_IP']}")
    return _exec(ctx, "provision nextcloud", do)


# ── 4. VPN jail + kill-switch + confined torrent/arr jails ───────────────────
def create_vpn_stack(ctx: Ctx, accept) -> tuple[bool, str]:
    if not ctx.profile.use_vpn_stack:
        return True, "vpn stack disabled in profile"
    st = ctx.stack()
    vpn = st["vpn"]
    confined = ", ".join(c["name"] for c in vpn["confined"])
    if not accept(f"Create VPN jail + kill-switch, confine: {confined}?"):
        return False, "declined"
    def do(c):
        rel = st["release"]
        # kernel WireGuard
        c.plat.kldload(c.sudo, *vpn.get("kmod", ["if_wg"]))
        # vpn jail
        if not c.plat.jail_exists(vpn["jail"]):
            c.plat.jail_create(c.sudo, vpn["jail"], rel, vpn["ip"], st["bridge"])
            c.plat.jail_pkg_install(c.sudo, vpn["jail"], vpn["pkg"])
        # render wg0.conf + pf kill-switch from the profile, into the vpn jail
        jail_root = f"/usr/local/bastille/jails/{vpn['jail']}/root"
        render_file(c.repo / "vpn" / "wg0.conf.tmpl",
                    Path(f"{jail_root}/usr/local/etc/wireguard/wg0.conf"),
                    c.v, mode=0o600)
        render_file(c.repo / "vpn" / "pf-killswitch.conf.tmpl",
                    Path(f"{jail_root}/etc/pf.conf"), c.v, mode=0o644)
        for k, val in vpn["rc"].items():
            c.plat.jail_sysrc(c.sudo, vpn["jail"], f"{k}={val}")
        c.plat.jail_service(c.sudo, vpn["jail"], "wireguard", "start")
        c.plat.jail_sysrc(c.sudo, vpn["jail"], "pf_enable=YES")
        c.plat.jail_service(c.sudo, vpn["jail"], "pf", "start")
        # confined jails: created, then their default route sent through vpn
        for cj in vpn["confined"]:
            if not c.plat.jail_exists(cj["name"]):
                c.plat.jail_create(c.sudo, cj["name"], rel, cj["ip"], st["bridge"])
                c.plat.jail_pkg_install(c.sudo, cj["name"], cj["pkg"])
            for k, val in (cj.get("rc") or {}).items():
                c.plat.jail_sysrc(c.sudo, cj["name"], f"{k}={val}")
            for m in (cj.get("mounts") or []):
                c.plat.jail_mount(c.sudo, cj["name"], m["host"], m["jail"],
                                  ro=m.get("ro", False))
            # route via the vpn jail's tunnel IP (no other default route exists)
            c.plat.jail_sysrc(c.sudo, cj["name"],
                              f"defaultrouter={vpn['ip']}")
            for svc in (cj.get("services") or []):
                c.plat.jail_service(c.sudo, cj["name"], svc, "start")
        return True, f"vpn + confined: {confined}"
    return _exec(ctx, "create vpn stack", do)


# ── 5. self-healing routine + cron ───────────────────────────────────────────
def install_daily_routine(ctx: Ctx, accept) -> tuple[bool, str]:
    if not ctx.profile.use_daily_routine:
        return True, "daily routine disabled in profile"
    if not accept("Install nightly self-heal routine + 03:00 cron?"):
        return False, "declined"
    def do(c):
        # State dir was ~/.hermes in earlier releases — carry an existing
        # one over so logs and state survive the rename.
        old_state = Path(c.v["HOME"]) / ".hermes"
        new_state = Path(c.v["HOME"]) / ".dbmedia"
        if old_state.is_dir() and not new_state.exists():
            old_state.rename(new_state)
        dst = new_state / "scripts" / "daily-routine.sh"
        render_file(c.tpl / "daily-routine.sh", dst, c.v, mode=0o755)
        entries = [f"0 3 * * * {dst} >/dev/null 2>&1"]
        if c.profile.vpn_rotate_hourly:
            rot = Path(c.v["HOME"]) / ".dbmedia" / "scripts" / "daily-routine.sh"
            entries.append(f"0 * * * * {rot} --quick >/dev/null 2>&1")
        c.plat.crontab_user(entries)
        return True, f"installed {dst} + cron"
    return _exec(ctx, "install daily routine", do)


# ── 6. dashboard (loopback HTTP + collector + KWin below-layer window) ───────
def install_dashboard(ctx: Ctx, accept) -> tuple[bool, str]:
    if not ctx.profile.use_dashboard:
        return True, "dashboard disabled in profile"
    if not accept("Install the KDE desktop status dashboard?"):
        return False, "declined"
    def do(c):
        home = Path(c.v["HOME"])
        src = c.tpl / "dashboard"
        bin_dir = home / ".local/bin"
        share = home / ".local/share/status-dashboard"
        conf = home / ".config/status-dashboard"
        for d in (bin_dir, share, conf):
            d.mkdir(parents=True, exist_ok=True)

        # Scripts + python modules -> ~/.local/bin, rendering {{MEDIA_POOL}} etc.
        # (data source is bastille/jls; the KWin below-layer rule is identical
        # because KDE Plasma uses the same KWin the Linux edition targeted.)
        for f in sorted(src.iterdir()):
            if f.suffix in (".py", ".sh"):
                render_file(f, bin_dir / f.name, c.v, mode=0o755)
        # The page carries no {{TOKENS}} — copy it verbatim, 644.
        render_file(src / "index.html", share / "index.html", c.v, mode=0o644)

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

        # AI panes: OpenRouter key (blank) + model slugs managed by
        # ai-panes-check.py; then run it once so model-pricing.json populates
        # and the paid/free pane labels + prices are correct on first paint.
        ds = conf / "deepseek.env"
        if not ds.exists():
            ds.write_text(
                "# chmod 600. One OpenRouter key powers every online AI pane.\n"
                "DEEPSEEK_API_KEY=\n"
                "DEEPSEEK_BASE_URL=https://openrouter.ai/api/v1\n"
                "# The block below is rewritten nightly by ai-panes-check.py.\n")
            ds.chmod(0o600)
        c.sudo.run(["sh", "-c",
                    f"su -m {c.profile.user} -c '{bin_dir}/ai-panes-check.py' "
                    f"|| {bin_dir}/ai-panes-check.py"], timeout=90)

        # Idempotent installer: cron collector + server watchdog, ttyd, autostart,
        # KWin rule. Best-effort — the collector/server work even if the desktop
        # bits are skipped on a headless box.
        rc = c.sudo.run(["sh", str(bin_dir / "status-dashboard-install.sh")],
                        timeout=300)
        return True, ("dashboard deployed to ~/.local/bin + ~/.local/share "
                      f"(installer rc={rc.returncode}); fill API keys in "
                      "~/.config/status-dashboard/media-keys.env")
    return _exec(ctx, "install dashboard", do)


ORDER = [
    ("Check FreeBSD",          check_freebsd),
    ("Host packages",          install_host_packages),
    ("Bastille bootstrap",     bootstrap_bastille),
    ("Media jails",            create_media_jails),
    ("Nextcloud",              create_nextcloud_stack),
    ("VPN stack + killswitch", create_vpn_stack),
    ("Self-heal routine",      install_daily_routine),
    ("Desktop dashboard",      install_dashboard),
]
