#!/bin/sh
# copperarch-install.sh — privileged backend for the CopperArch graphical
# installer. The Qt GUI never partitions anything itself; it calls this, which
# drives FreeBSD's OWN bsdinstall subcommands in the exact order the scripted
# installer uses (verified against usr.sbin/bsdinstall/scripts/script in the
# 15.1 source): zfsboot -> mount -> distextract -> bootconfig -> config ->
# chroot post-install -> entropy -> umount. So ZFS/partitioning is FreeBSD's,
# not a reimplementation; we only collect answers and report progress.
#
# Modes:
#   --list-disks   JSON array of installable disks (for the Disk page)
#   --keymaps      newline list of keymap names
#   --timezones    newline list of time zones
#   --install      read answers (key=value lines) on stdin, perform the install,
#                  emitting PROGRESS/STEP/LOG/DONE tokens the GUI parses
#   --reboot       reboot the machine
#
# Answer keys: disk zfsVdev swapGiB hostname username fullname password
#              rootPassword timezone keymap enableMediaStack
set -u

CHROOT=/mnt
DISTDIR=${BSDINSTALL_DISTDIR:-/usr/freebsd-dist}
POOL=zroot
PROJECT_SRC=/usr/local/freebsd-media-setup

emit() { printf '%s\n' "$*"; }
step() { emit "STEP $*"; }
prog() { emit "PROGRESS $*"; }
log()  { emit "LOG $*"; }
die()  { emit "DONE fail $*"; exit 1; }

# ── disk / choice enumeration ───────────────────────────────────────────────
list_disks() {
    printf '['
    first=1
    for d in $(sysctl -n kern.disks 2>/dev/null); do
        case "$d" in cd*|md*|fd*|cd[0-9]*) continue ;; esac
        # diskinfo columns: name sectorsize mediasize(bytes) sectors ...
        bytes=$(diskinfo "$d" 2>/dev/null | awk '{print $3}')
        [ -n "$bytes" ] || bytes=0
        descr=$(geom disk list "$d" 2>/dev/null \
                 | awk -F'descr: ' '/descr:/{print $2; exit}')
        [ -n "$descr" ] || descr="$d"
        # escape double quotes/backslashes for JSON
        descr=$(printf '%s' "$descr" | sed 's/\\/\\\\/g; s/"/\\"/g')
        [ $first -eq 1 ] || printf ','
        first=0
        printf '{"device":"%s","descr":"%s","bytes":%s}' "$d" "$descr" "$bytes"
    done
    printf ']\n'
}

list_keymaps() {
    if [ -d /usr/share/vt/keymaps ]; then
        find /usr/share/vt/keymaps -name '*.kbd' 2>/dev/null \
            | sed 's#.*/##; s/\.kbd$//' | sort -u
    else
        printf 'us\nuk\nde\nfr\nes\nit\n'
    fi
}

list_timezones() {
    # A curated common set first; the field accepts any zoneinfo name.
    cat <<'EOF'
Europe/London
Europe/Dublin
Europe/Paris
Europe/Berlin
Europe/Madrid
Europe/Rome
Europe/Amsterdam
America/New_York
America/Chicago
America/Denver
America/Los_Angeles
America/Toronto
Australia/Sydney
Asia/Tokyo
Asia/Singapore
UTC
EOF
}

# ── install ─────────────────────────────────────────────────────────────────
read_answers() {
    DISK=""; ZVDEV="stripe"; SWAP="8"; HOSTNAME="copperarch-media"
    USERNAME="copper"; FULLNAME=""; PASSWORD=""; ROOTPW=""
    TZ="Europe/London"; KEYMAP="us"; MEDIA="1"; DESKTOP="kde"
    while IFS= read -r line; do
        key=${line%%=*}; val=${line#*=}
        case "$key" in
            disk)             DISK=$val ;;
            desktop)          DESKTOP=$val ;;
            zfsVdev)          ZVDEV=$val ;;
            swapGiB)          SWAP=$val ;;
            hostname)         HOSTNAME=$val ;;
            username)         USERNAME=$val ;;
            fullname)         FULLNAME=$val ;;
            password)         PASSWORD=$val ;;
            rootPassword)     ROOTPW=$val ;;
            timezone)         TZ=$val ;;
            keymap)           KEYMAP=$val ;;
            enableMediaStack) MEDIA=$val ;;
        esac
    done
}

run_postinstall() {
    # Mirrors how bsdinstall's scripted path runs the post-install script inside
    # the chroot. All per-host config lives here (the `script` path does not run
    # rootpass/time/adduser itself — only zfsboot/extract/config do).
    cat > "$CHROOT/tmp/copperarch-post" <<POST
#!/bin/sh
set -e
sysrc hostname="$HOSTNAME"
sysrc ifconfig_DEFAULT="DHCP"
sysrc sshd_enable="YES"
sysrc zfs_enable="YES"
sysrc ntpd_enable="YES"
sysrc dumpdev="AUTO"
sysrc keymap="$KEYMAP"

# ── desktop + media stack: finished on FIRST BOOT, not here ─────────────────
# This chroot has no working DNS and no writable pkg state, so a pkg install
# here silently fails. Stage the first-boot service (copperbsd_firstboot, from
# installer/configuration/firstboot.sh) and its inputs instead; it downloads the
# chosen desktop on the installed system, which has real network.
install -d /usr/local/share/copperbsd /usr/local/etc/rc.d
if [ -d /tmp/copperbsd-desktop ]; then
    cp /tmp/copperbsd-desktop/desktops.conf /usr/local/share/copperbsd/
    install -d /usr/local/share/copperbsd/desktop
    cp -a /tmp/copperbsd-desktop/bin /tmp/copperbsd-desktop/etc \
          /tmp/copperbsd-desktop/wayland-sessions \
          /usr/local/share/copperbsd/desktop/ 2>/dev/null || true
    install -m 555 /tmp/copperbsd-desktop/firstboot.sh \
          /usr/local/etc/rc.d/copperbsd_firstboot
    [ -d /tmp/copperbsd-desktop/dashboard ] && \
        cp -a /tmp/copperbsd-desktop/dashboard /usr/local/share/copperbsd/dashboard
    # Installed version + the updater behind the dashboard's Update button.
    [ -f /tmp/copperbsd-desktop/VERSION ] && \
        install -m 644 /tmp/copperbsd-desktop/VERSION /usr/local/share/copperbsd/VERSION
    [ -f /tmp/copperbsd-desktop/copperbsd-update.sh ] && \
        install -d /usr/local/libexec && \
        install -m 555 /tmp/copperbsd-desktop/copperbsd-update.sh \
            /usr/local/libexec/copperbsd-update
fi
cat > /usr/local/share/copperbsd/firstboot.conf <<FBCONF
DESKTOP="$DESKTOP"
USERNAME="$USERNAME"
MEDIA="$MEDIA"
KEYMAP="$KEYMAP"
FBCONF
sysrc copperbsd_firstboot_enable="YES"
printf '%s\n' "$DESKTOP" > /etc/copperbsd-desktop

# time zone
if [ -f "/usr/share/zoneinfo/$TZ" ]; then
    cp "/usr/share/zoneinfo/$TZ" /etc/localtime
    printf '%s\n' "$TZ" > /var/db/zoneinfo
fi

# root password + the admin user (passwords arrive on stdin via pw -h 0)
printf '%s' "$ROOTPW" | pw usermod root -h 0
pw useradd -n "$USERNAME" -c "$FULLNAME" -m -G wheel,operator,video -s /bin/sh
printf '%s' "$PASSWORD" | pw usermod "$USERNAME" -h 0

POST
    chmod +x "$CHROOT/tmp/copperarch-post"
    # Copy the project into the installed system so first boot can run it.
    [ -d "$PROJECT_SRC" ] && cp -a "$PROJECT_SRC" "$CHROOT/usr/local/" 2>/dev/null || true
    # Stage the desktop package groups + session assets into the chroot so the
    # post-install can install the chosen desktop. REPO = the CopperBSD tree on
    # the live medium (falls back to this script's location).
    REPO="${COPPERBSD_REPO:-/usr/local/CopperBSD}"
    [ -d "$REPO/packages" ] || REPO="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)"
    if [ -d "$REPO/packages" ]; then
        install -d "$CHROOT/tmp/copperbsd-desktop"
        cp "$REPO/packages/desktops.conf" "$CHROOT/tmp/copperbsd-desktop/" 2>/dev/null || true
        cp "$REPO/installer/configuration/firstboot.sh" "$CHROOT/tmp/copperbsd-desktop/" || return 1
        [ -d "$REPO/dashboard" ] && cp -a "$REPO/dashboard" "$CHROOT/tmp/copperbsd-desktop/dashboard"
        cp "$REPO/VERSION" "$CHROOT/tmp/copperbsd-desktop/" 2>/dev/null || true
        cp "$REPO/installer/configuration/copperbsd-update.sh" \
           "$CHROOT/tmp/copperbsd-desktop/" 2>/dev/null || true
        cp -a "$REPO/installer/configuration/desktop/." \
              "$CHROOT/tmp/copperbsd-desktop/" 2>/dev/null || true
    fi
    chroot "$CHROOT" /tmp/copperarch-post || return 1
    rm -rf "$CHROOT/tmp/copperarch-post" "$CHROOT/tmp/copperbsd-desktop"
}

do_install() {
    read_answers
    [ -n "$DISK" ] || die "No disk selected."
    [ -d "$DISTDIR" ] || [ "${COPPERARCH_FORCE:-0}" = "1" ] || \
        die "No distribution sets at $DISTDIR — not running from install media."

    export BSDINSTALL_CHROOT="$CHROOT"
    export BSDINSTALL_DISTDIR="$DISTDIR"
    export DISTRIBUTIONS="kernel.txz base.txz"
    export ZFSBOOT_VDEV_TYPE="$ZVDEV"
    export ZFSBOOT_DISKS="$DISK"
    export ZFSBOOT_SWAP_SIZE="${SWAP}g"
    export ZFSBOOT_POOL_NAME="$POOL"
    export nonInteractive="YES"
    export ZFSBOOT_CONFIRM_LAYOUT=0

    step "Partitioning $DISK as ZFS (zroot)"; prog 6
    log "bsdinstall zfsboot on $DISK ($ZVDEV, ${SWAP}G swap)"
    bsdinstall zfsboot  >&2 || die "ZFS partitioning failed."
    prog 18

    step "Mounting the new system"
    bsdinstall mount    >&2 || die "Mounting the new pool failed."
    prog 24

    step "Extracting the FreeBSD base system"
    ( bsdinstall distextract >&2 ) &
    dpid=$!
    p=24
    while kill -0 "$dpid" 2>/dev/null; do
        sleep 2
        [ "$p" -lt 78 ] && p=$((p + 2)) && prog "$p"
    done
    wait "$dpid" || die "Extracting the base system failed."
    prog 80

    step "Installing the bootloader"
    bsdinstall bootconfig >&2 || die "Bootloader configuration failed."
    prog 85

    step "Writing system configuration"
    bsdinstall config   >&2 || die "Saving configuration failed."
    [ -f "$CHROOT/etc/resolv.conf" ] || \
        cp /etc/resolv.conf "$CHROOT/etc/resolv.conf" 2>/dev/null || true
    prog 89

    step "Creating your account and first-boot setup"
    run_postinstall || die "Post-install configuration failed."
    prog 96

    bsdinstall entropy >&2 || true
    bsdinstall umount  >&2 || true
    zpool export "$POOL" 2>/dev/null || true
    prog 100
    emit "DONE ok"
}

case "${1:-}" in
    --list-disks) list_disks ;;
    --keymaps)    list_keymaps ;;
    --timezones)  list_timezones ;;
    --reboot)     shutdown -r now ;;
    --install)    do_install ;;
    *) echo "usage: $0 --list-disks|--keymaps|--timezones|--install|--reboot" >&2
       exit 2 ;;
esac
