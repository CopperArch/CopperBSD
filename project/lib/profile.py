"""Install profile — FreeBSD edition.

Same idea as the Linux edition (pure-data YAML of your choices, chmod 600),
but the VPN section carries a WireGuard keypair instead of gluetun/OpenVPN
username+password, because on FreeBSD the tunnel is kernel WireGuard (if_wg),
not a container. Docker-only knobs (tugtainer secret, immich DB) are dropped.
"""
from __future__ import annotations

import re
import secrets
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None


def _gen_secret() -> str:
    return secrets.token_hex(16)


# Endpoint host -> provider name, for labelling the VPN on the dashboard when
# no name was given. Anything else is somebody's own server.
VPN_HOST_NAMES = (
    ("protonvpn", "Proton VPN"), ("windscribe", "Windscribe"),
    ("whiskergalaxy", "Windscribe"), ("surfshark", "Surfshark"),
    ("mullvad", "Mullvad"), ("nordvpn", "NordVPN"), ("ivpn", "IVPN"),
    ("privateinternetaccess", "Private Internet Access"), ("airvpn", "AirVPN"),
    ("torguard", "TorGuard"), ("expressvpn", "ExpressVPN"),
)


def vpn_label(name, endpoint):
    """Name shown for the active VPN: the one given, else guessed from the
    endpoint, else 'Custom VPN' (your own server or an unlisted provider)."""
    if (name or "").strip():
        return name.strip()[:40]
    host = (endpoint or "").rsplit(":", 1)[0].lower()
    for needle, label in VPN_HOST_NAMES:
        if needle in host:
            return label
    return "Custom VPN" if host else ""


@dataclass
class Profile:
    # identity / network
    user: str = "copper"
    lan_ip: str = ""
    lan_cidr: str = "192.168.1.0/24"
    host_ip: str = ""
    jail_subnet: str = "10.17.0"
    jail_release: str = "15.1-RELEASE"
    timezone: str = "Europe/London"
    # domains
    domain: str = ""
    jellyfin_public_url: str = ""
    nextcloud_domain: str = ""         # e.g. cloud.example.com (blank = LAN only)
    # storage (ZFS datasets/paths on the host, nullfs-mounted into jails)
    media_pool: str = "/mnt/storage"
    nextcloud_data: str = "/mnt/nextcloud-data"
    # nextcloud (the Immich replacement — photos/files)
    use_nextcloud: bool = True
    nc_admin_user: str = "admin"
    nc_admin_password: str = ""
    nc_db_password: str = ""
    # vpn — WireGuard (from your provider's wg config)
    wg_private_key: str = ""
    wg_address: str = "10.2.0.2/32"
    wg_dns: str = "10.2.0.1"
    wg_peer_public_key: str = ""
    wg_endpoint: str = ""              # host:port
    wg_endpoint_ip: str = ""           # bare IP (for the pf kill-switch)
    wg_endpoint_port: str = "51820"
    wg_preshared_key: str = ""         # optional; many self-hosted servers use one
    vpn_provider: str = ""             # name shown on the dashboard ("Mullvad",
                                       # "Home server"...); blank = guessed
    vpn_rotate_hourly: bool = True
    # components
    use_media_stack: bool = True
    use_vpn_stack: bool = True
    use_dashboard: bool = True
    use_daily_routine: bool = True
    use_alerts: bool = False
    # secrets
    plex_claim: str = ""
    qbit_user: str = "admin"
    qbit_password: str = ""
    # alerts (SMTP)
    smtp_host: str = ""
    smtp_port: str = "587"
    smtp_user: str = ""
    smtp_pass: str = ""
    mail_from: str = ""
    mail_to: str = ""

    def render_vars(self) -> dict:
        user = self.user or "copper"
        pool = self.media_pool or "/mnt/storage"
        ep = self.wg_endpoint or ""
        ep_ip = self.wg_endpoint_ip or (ep.rsplit(":", 1)[0] if ":" in ep else ep)
        ep_pt = self.wg_endpoint_port or (ep.rsplit(":", 1)[1] if ":" in ep else "51820")
        return {
            "HOME": f"/home/{user}",
            "DASH_USER": user,
            "LAN_IP": self.lan_ip or "127.0.0.1",
            "LAN_CIDR": self.lan_cidr,
            "HOST_IP": self.host_ip or self.lan_ip or "127.0.0.1",
            "SUBNET": self.jail_subnet,
            "DOMAIN": self.domain,
            "JELLYFIN_PUBLIC_URL": self.jellyfin_public_url,
            "NEXTCLOUD_DOMAIN": self.nextcloud_domain,
            "NC_ADMIN_USER": self.nc_admin_user,
            "NC_ADMIN_PASSWORD": self.nc_admin_password,
            "NC_DB_PASSWORD": self.nc_db_password,
            "NC_DB_HOST": f"{self.jail_subnet}.16",
            "NC_JAIL_IP": f"{self.jail_subnet}.17",
            "TZ": self.timezone or "UTC",
            "MEDIA_POOL": pool,
            "NEXTCLOUD_DATA": self.nextcloud_data or f"{pool}/nextcloud-data",
            "PLEX_CLAIM": self.plex_claim,
            "QBIT_USER": self.qbit_user,
            "QBIT_PASSWORD": self.qbit_password,
            "WG_PRIVATE_KEY": self.wg_private_key,
            "WG_ADDRESS": self.wg_address,
            "WG_DNS": self.wg_dns,
            "WG_PEER_PUBLIC_KEY": self.wg_peer_public_key,
            "WG_ENDPOINT": ep,
            "WG_ENDPOINT_IP": ep_ip,
            "WG_ENDPOINT_PORT": ep_pt,
            "WG_PSK_LINE": (f"PresharedKey = {self.wg_preshared_key}"
                            if self.wg_preshared_key else "# (no pre-shared key)"),
        }

    def to_yaml(self) -> str:
        d = {"meta": {"created": datetime.now(timezone.utc).isoformat(),
                      "installer": "freebsd-media-setup-with-dash"}}
        for f in self.__dataclass_fields__:
            d[f] = getattr(self, f)
        return yaml.safe_dump(d, sort_keys=False, default_flow_style=False)

    def save(self, path: Path) -> Path:
        Path(path).write_text(self.to_yaml())
        Path(path).chmod(0o600)
        return Path(path)

    @classmethod
    def from_yaml(cls, path: Path) -> "Profile":
        data = yaml.safe_load(Path(path).read_text()) or {}
        p = cls()
        for f in p.__dataclass_fields__:
            if f in data and data[f] is not None:
                setattr(p, f, data[f])
        return p

    def validate(self) -> list[str]:
        errs = []
        if (self.use_media_stack or self.use_vpn_stack) and not \
                re.fullmatch(r"[0-9a-fA-F.:]+", self.lan_ip or ""):
            errs.append("lan_ip must be a valid IPv4/IPv6 address")
        if self.use_vpn_stack and not (self.wg_private_key and
                                       self.wg_peer_public_key and self.wg_endpoint):
            errs.append("wg_private_key / wg_peer_public_key / wg_endpoint "
                        "required when the VPN stack is enabled")
        if self.use_alerts and not self.smtp_host:
            errs.append("smtp settings required when alerts are enabled")
        if self.use_nextcloud and not (self.nc_admin_password and self.nc_db_password):
            errs.append("nc_admin_password / nc_db_password required when "
                        "Nextcloud is enabled (leave blank to auto-generate via "
                        "with_generated_secrets, or set your own)")
        return errs

    @classmethod
    def with_generated_secrets(cls) -> "Profile":
        p = cls()
        p.qbit_password = _gen_secret()
        p.nc_admin_password = _gen_secret()
        p.nc_db_password = _gen_secret()
        return p
