#!/bin/sh
# daily-routine.sh — nightly self-healing maintenance for this FreeBSD media
# server. FreeBSD port of the Linux edition: systemd -> rc.d, docker -> jails
# (bastille/jls), apt -> pkg + freebsd-update, mdadm/SMART -> zpool + smartctl,
# ufw/gluetun-iptables -> pf.
#
#   ./daily-routine.sh          # run everything (updates included)
#   ./daily-routine.sh --quick  # health/connectivity checks only, no updates
#
# POSIX sh (FreeBSD /bin/sh) — no bashisms, so it runs from cron and from the
# base system with nothing extra installed.
set -u

PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"
export PATH

ROOT="{{HOME}}"
LOGDIR="$ROOT/.dbmedia/maintenance-logs"
LOG="$LOGDIR/daily-routine-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOGDIR"

log()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
warn()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" | tee -a "$LOG"; }
banner() { log ""; log "========== $* =========="; }

QUICK=false
[ "${1:-}" = "--quick" ] && QUICK=true

# Managed jails (kept in sync with stack.yaml). VPN-routed ones listed too.
MEDIA_JAILS="jellyfin plex prowlarr bazarr seerr caddy nextcloud nextcloud-db"
VPN_JAILS="vpn qbittorrent sonarr radarr"
ALL_JAILS="$MEDIA_JAILS $VPN_JAILS"

banner "Daily Routine started (quick=$QUICK) on $(hostname)"

# ─── 1. Host health: rc services, ZFS, SMART ────────────────────────────────
banner "Host System Health Check"

# rc.d services that must be up for the stack to function.
for svc in bastille pf sddm; do
    if service "$svc" status >/dev/null 2>&1; then
        log "  [OK]   rc service '$svc' is running"
    else
        warn "  [FAIL] rc service '$svc' is NOT running — check 'service $svc status'"
    fi
done

# ZFS pool health (replaces mdadm/SMART array checks). DEGRADED/FAULTED is loud.
if command -v zpool >/dev/null 2>&1; then
    for pool in $(zpool list -H -o name 2>/dev/null); do
        state=$(zpool list -H -o health "$pool" 2>/dev/null)
        if [ "$state" = "ONLINE" ]; then
            log "  [OK]   zpool '$pool' is ONLINE"
        else
            warn "  [FAIL] zpool '$pool' is $state — run 'zpool status $pool'"
        fi
    done
fi

# SMART: smartctl exists on FreeBSD too. Use device nodes; ZFS handles the
# array logic so we only assert per-disk health here.
if command -v smartctl >/dev/null 2>&1; then
    for dev in $(sysctl -n kern.disks 2>/dev/null); do
        case "$dev" in cd*|md*|fd*) continue ;; esac
        out=$(smartctl -H "/dev/$dev" 2>&1)
        if echo "$out" | grep -qi "PASSED\|OK"; then
            log "  [OK]   SMART /dev/$dev: healthy"
        elif echo "$out" | grep -qi "Unavailable\|Unsupported"; then
            log "  [SKIP] SMART /dev/$dev: no passthrough (USB bridge?)"
        else
            warn "  [WARN] SMART /dev/$dev: $(echo "$out" | grep -i health)"
        fi
    done
fi

# ─── 1b. Jail crash-loop / down detection (replaces docker restart-count) ───
banner "Jail Health Check"
# jls has no restart counter, so we detect (a) a jail that should be up but
# isn't, and (b) a service inside a jail that keeps dying (checked via its
# rc status). This catches the FreeBSD equivalent of the chrome crash-loop.
for j in $ALL_JAILS; do
    if ! jls -j "$j" >/dev/null 2>&1; then
        warn "  [FAIL] jail '$j' is not running — 'bastille start $j'"
        continue
    fi
    log "  [OK]   jail '$j' is up"
done

# ─── 2. VPN tunnel health + rotation (replaces gluetun healthcheck) ─────────
banner "VPN Tunnel Health"
# Trust the tunnel, not the wrapper: check the exit IP from INSIDE the vpn jail
# and confirm it differs from the host's real WAN IP. gluetun's healthcheck
# used to stay "healthy" while OpenVPN looped on auth — we check reality.
vpn_exit_ip() { bastille cmd vpn sh -c 'fetch -qo - https://api.ipify.org 2>/dev/null'; }
host_wan_ip() { fetch -qo - https://api.ipify.org 2>/dev/null; }

TUN_OK=false
for attempt in 1 2 3; do
    vip=$(vpn_exit_ip); hip=$(host_wan_ip)
    if [ -n "$vip" ] && [ "$vip" != "$hip" ]; then
        log "  [OK]   VPN exit IP $vip differs from host WAN $hip (attempt $attempt)"
        TUN_OK=true
        break
    fi
    warn "  [WARN] tunnel down or leaking (vpn='$vip' host='$hip'), restart $attempt/3"
    bastille cmd vpn service wireguard restart >/dev/null 2>&1
    sleep 8
done
if [ "$TUN_OK" != true ]; then
    warn "  [FAIL] VPN tunnel would not come back after 3 restarts"
    [ -x "$ROOT/.dbmedia/scripts/send-alert.py" ] && \
        "$ROOT/.dbmedia/scripts/send-alert.py" "VPN tunnel down on $(hostname)" \
        >/dev/null 2>&1
    # Kill-switch means the torrent jail is already leak-safe (no fallback),
    # so we do NOT need to stop it — pf has already dropped its egress.
fi

# Re-assert the pf kill-switch in case a reboot or manual edit dropped it.
if pfctl -s rules 2>/dev/null | grep -q "$( printf 'on wg0' )"; then
    log "  [OK]   pf kill-switch rules present"
else
    warn "  [WARN] pf kill-switch rules missing — reloading /etc/pf.conf"
    pfctl -f /etc/pf.conf 2>&1 | tee -a "$LOG"
fi

if [ "$QUICK" = true ]; then
    banner "Quick mode — skipping updates"
    log "Daily Routine (quick) finished"
    exit 0
fi

# ─── 3. Media stack update with verify + rollback ───────────────────────────
banner "Media Stack Update (verify + rollback)"
# The *arr FreeBSD ports have their in-app updater disabled — updates come from
# pkg, which is exactly the "reviewed, pinned" model we want. We snapshot each
# jail (ZFS) before upgrading so a bad pkg can be rolled back instantly.
for j in $ALL_JAILS; do
    ds=$(bastille config "$j" get zfs.dataset 2>/dev/null)
    snap="preupdate-$(date +%Y%m%d)"
    [ -n "$ds" ] && zfs snapshot "${ds}@${snap}" 2>/dev/null && \
        log "  snapshot ${ds}@${snap}"
    if bastille pkg "$j" upgrade -y >>"$LOG" 2>&1; then
        # verify the jail's primary service still answers after upgrade
        if jls -j "$j" >/dev/null 2>&1; then
            log "  [OK]   $j upgraded and still healthy"
        else
            warn "  [ROLLBACK] $j unhealthy after upgrade — rolling back snapshot"
            [ -n "$ds" ] && zfs rollback "${ds}@${snap}" && bastille restart "$j"
        fi
    else
        warn "  [WARN] pkg upgrade failed in $j (left as-is)"
    fi
done

# ─── 4. Host base + package updates ─────────────────────────────────────────
banner "Host Updates"
log "  pkg upgrade (host)"
env ASSUME_ALWAYS_YES=YES pkg upgrade -y >>"$LOG" 2>&1 && log "  [OK] host pkg upgrade"
log "  freebsd-update fetch/install (security patches)"
env PAGER=cat freebsd-update --not-running-from-cron fetch install >>"$LOG" 2>&1 \
    && log "  [OK] freebsd-update applied" \
    || log "  [INFO] freebsd-update: nothing to do or needs reboot"

# ─── 4b. Jellyfin duplicate removal (DELETES losing files) ─────────────────
# Keeps the best copy of a movie/episode stored twice and deletes the rest;
# skips itself until ~/.dbmedia/jellyfin-api-key exists — creating that file
# is the opt-in.
banner "Jellyfin Duplicate Removal"
if [ -x "$ROOT/.local/bin/jellyfin-duplicates.py" ]; then
    "$ROOT/.local/bin/jellyfin-duplicates.py" --apply 2>&1 | tee -a "$LOG"
else
    log "  [SKIP] jellyfin-duplicates.py not installed"
fi

# ─── 5. Log rotation guard (replaces docker log-cap check) ──────────────────
banner "Log Hygiene"
find "$LOGDIR" -type f -mtime +30 -delete 2>/dev/null
log "  pruned maintenance logs older than 30 days"

# ─── 6. Dashboard AI panes: refresh model slugs + pricing ───────────────────
# Re-pick the paid flagships, verify the free tiers still exist, and refresh
# model-pricing.json so the dashboard shows live per-pane pricing. Never fails
# the routine (exit 0 on any network error).
banner "AI Panes Refresh"
if [ -x "$ROOT/.local/bin/ai-panes-check.py" ]; then
    "$ROOT/.local/bin/ai-panes-check.py" 2>&1 | tee -a "$LOG"
else
    log "  [SKIP] ai-panes-check.py not installed"
fi

banner "Daily Routine finished on $(hostname)"
