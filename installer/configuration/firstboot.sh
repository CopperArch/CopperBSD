#!/bin/sh
# PROVIDE: copperbsd_firstboot
# REQUIRE: NETWORKING syslogd
# BEFORE: LOGIN
# KEYWORD: nojail
#
# copperbsd_firstboot — runs ONCE on the first boot of an installed CopperBSD.
# The install itself lays down only the FreeBSD base; the chosen desktop and
# the media stack are downloaded here, because the installed system has working
# DNS and a writable pkg root (the install chroot has neither).
#
# Inputs, written by the installer (copperarch-install.sh):
#   /usr/local/share/copperbsd/firstboot.conf   DESKTOP USERNAME MEDIA KEYMAP
#   /usr/local/share/copperbsd/desktops.conf    desktop_pkgs(), DESKTOP_RC
#   /usr/local/share/copperbsd/desktop/         session wrappers/configs
# Output: /var/log/copperbsd-firstboot.log (also echoed to the console).

. /etc/rc.subr

name=copperbsd_firstboot
rcvar=copperbsd_firstboot_enable
start_cmd=firstboot_start
stop_cmd=:

# rc runs services with a minimal PATH; the ports tools live in /usr/local.
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
export PATH

SHARE=/usr/local/share/copperbsd
LOG=/var/log/copperbsd-firstboot.log
DONE=/var/db/copperbsd-firstboot.done
NET_WAIT_TRIES=60

say() { printf '[copperbsd-firstboot] %s\n' "$*" | tee -a "$LOG" >/dev/console; }

wait_for_network() {
    say "waiting for the network..."
    i=0
    while [ "$i" -lt "$NET_WAIT_TRIES" ]; do
        if fetch -q -T 5 -o /dev/null http://pkg.freebsd.org/ 2>/dev/null; then
            return 0
        fi
        i=$((i + 1)); sleep 3
    done
    return 1
}

pkg_install() {
    env ASSUME_ALWAYS_YES=YES pkg install -y "$@" >>"$LOG" 2>&1
}

# -- native dashboard --------------------------------------------------------
install_dashboard()
{
    command -v copper-dashboard >/dev/null 2>&1 && return 0
    say "building the CopperBSD dashboard"
    # dejavu: the dashboard's own fonts have no arrows or check marks; without
    # a fallback font its button icons draw as empty boxes.
    pkg_install cmake ninja pkgconf qt6-base qt6-declarative qt6-svg \
        kf6-kirigami kf6-qqc2-desktop-style kf6-kio kf6-breeze-icons dejavu || \
        say "WARNING: dashboard build dependencies failed (see $LOG)"
    SRC="$SHARE/dashboard"
    BLD=/var/tmp/copper-dashboard-build
    rm -rf "$BLD"
    if cmake -S "$SRC" -B "$BLD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_INSTALL_PREFIX=/usr/local >>"$LOG" 2>&1 \
       && cmake --build "$BLD" >>"$LOG" 2>&1 \
       && cmake --install "$BLD" >>"$LOG" 2>&1; then
        say "dashboard installed"
    else
        say "WARNING: the dashboard failed to build (see $LOG)"
    fi
    rm -rf "$BLD"
    # build-only tools are not needed at runtime
    env ASSUME_ALWAYS_YES=YES pkg delete -y cmake ninja >>"$LOG" 2>&1 || true
}

# -- media stack -------------------------------------------------------------
setup_media_stack()
{
    PROJ=/usr/local/freebsd-media-setup
    PROFILE="$SHARE/profile.yaml"
    # Bastille needs to know which ZFS pool to use and a bridge for the jails.
    sysrc bastille_enable=YES >>"$LOG" 2>&1
    sed -i '' -e 's|^bastille_zfs_enable=.*|bastille_zfs_enable="YES"|' \
              -e 's|^bastille_zfs_zpool=.*|bastille_zfs_zpool="zroot"|' \
              /usr/local/etc/bastille/bastille.conf
    if ! ifconfig bastille0 >/dev/null 2>&1; then
        sysrc cloned_interfaces+="bridge0" ifconfig_bridge0_name="bastille0" >>"$LOG" 2>&1
        ifconfig bridge0 create name bastille0 >>"$LOG" 2>&1
    fi
    # The project's hands-off profile (VPN and Nextcloud off) with this
    # machine's user filled in. The installer works out the LAN address, sets
    # up address translation for the jails, and runs as root: it writes pf
    # rules, jail configs and root's crontab, then hands the dashboard's files
    # to $USERNAME.
    sed -e "s|^user:.*|user: $USERNAME|" \
        "$PROJ/profiles/unattended.yaml" > "$PROFILE"
    chmod 644 "$PROFILE"
    python3.12 "$PROJ/install.py" --cli --profile "$PROFILE" --yes \
        >>"$LOG" 2>&1 || say "WARNING: the media-stack installer reported errors (see $LOG)"
}

# -- display ------------------------------------------------------------------
# With a KMS GPU (AMD/Intel via drm-kmod) Xorg autodetects everything and needs
# no help. Without one (VMs, plain framebuffers) the VESA driver reports no
# monitor timings or refresh rate, which left Plasma with an off-screen panel
# ("requesting unexisting screen geometry", "Bogus refresh rate 0"). Give Xorg
# an explicit 1920x1080 mode and tell KWin the refresh rate.
configure_display()
{
    if pciconf -lv 2>/dev/null | grep -qiE 'AMD|Radeon|Intel.*Graphics|NVIDIA'; then
        say "GPU with a KMS driver detected -- leaving Xorg on autodetect"
    else
        say "no KMS GPU -- configuring a 1920x1080 framebuffer display"
        mkdir -p /usr/local/etc/X11/xorg.conf.d
        cat > /usr/local/etc/X11/xorg.conf.d/20-copperbsd-fb.conf <<'XORG'
Section "Monitor"
    Identifier "Monitor0"
    HorizSync 30-140
    VertRefresh 50-75
    DisplaySize 508 286
    Modeline "1920x1080" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync
EndSection
Section "Device"
    Identifier "Card0"
    Driver "vesa"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "Card0"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Virtual 1920 1080
        Modes "1920x1080"
    EndSubSection
EndSection
XORG
    fi
    # Per-user (Plasma reads ~/.config/plasma-workspace/env at login; the
    # system-wide directory is not honoured by this build).
    H="/home/$USERNAME/.config/plasma-workspace/env"
    mkdir -p "$H"
    printf '#!/bin/sh\n# Framebuffer X drivers report 0 Hz via RandR; give KWin the real rate.\nexport KWIN_X11_REFRESH_RATE=60000\n' \
        > "$H/10-copperbsd-refresh.sh"
    chmod 755 "$H/10-copperbsd-refresh.sh"
    chown -R "$USERNAME" "/home/$USERNAME/.config" 2>/dev/null || true
    su -l "$USERNAME" -c "kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false" >>"$LOG" 2>&1 || true
}

firstboot_start()
{
    [ -e "$DONE" ] && return 0
    . "$SHARE/firstboot.conf"
    . "$SHARE/desktops.conf"

    say "setting up your $DESKTOP desktop (this downloads packages and can take a while)"
    if ! wait_for_network; then
        say "no network -- will retry on the next boot"
        return 0
    fi

    env ASSUME_ALWAYS_YES=YES pkg bootstrap -f >>"$LOG" 2>&1 || true
    env ASSUME_ALWAYS_YES=YES pkg update -f   >>"$LOG" 2>&1 || {
        say "pkg update failed -- will retry on the next boot"; return 0; }

    # Desktop group + the X server/drivers/fonts the SDDM greeter and X11
    # sessions need (the framebuffer drivers cover VMs with no KMS GPU).
    say "installing the desktop packages"
    # shellcheck disable=SC2046
    pkg_install $(desktop_pkgs "$DESKTOP") \
        xorg-server xauth xf86-input-libinput xf86-video-scfb xf86-video-vesa \
        drm-kmod dejavu pipewire wireplumber xkbcomp setxkbmap indexinfo xmlcatmgr || say "WARNING: some desktop packages failed (see $LOG)"

    for kv in $DESKTOP_RC; do sysrc "$kv" >>"$LOG" 2>&1; done
    configure_display
    if pciconf -lv 2>/dev/null | grep -qiE 'AMD|Radeon'; then
        sysrc kld_list+="amdgpu" >>"$LOG" 2>&1
    elif pciconf -lv 2>/dev/null | grep -qiE 'Intel.*Graphics'; then
        sysrc kld_list+="i915kms" >>"$LOG" 2>&1
    fi

    # Session wrappers/configs for the tiling Wayland desktops.
    D="$SHARE/desktop"
    install -d /usr/local/share/wayland-sessions /usr/local/etc/niri /usr/local/etc/xdg/quickshell
    cp "$D"/wayland-sessions/*.desktop /usr/local/share/wayland-sessions/ 2>/dev/null || true
    for w in niri-session mangowc-session; do
        [ -f "$D/bin/$w" ] && install -m 755 "$D/bin/$w" /usr/local/bin/
    done
    [ -f "$D/etc/niri/config.kdl" ] && cp "$D/etc/niri/config.kdl" /usr/local/etc/niri/ &&
        sed -i '' "s/layout \"us\"/layout \"$KEYMAP\"/" /usr/local/etc/niri/config.kdl
    [ -f "$D/etc/xdg/quickshell/shell.qml" ] &&
        cp "$D/etc/xdg/quickshell/shell.qml" /usr/local/etc/xdg/quickshell/

    # Default session in the SDDM greeter: X11 Plasma (the stable one on FreeBSD).
    case "$DESKTOP" in
        niri) SESS=niri ;; mangowc) SESS=mangowc ;; gnome) SESS=gnome ;;
        xfce) SESS=xfce ;; *) SESS=plasmax11 ;;
    esac
    printf '[Desktop]\nSession=%s\n' "$SESS" > "/home/$USERNAME/.dmrc"
    chown "$USERNAME" "/home/$USERNAME/.dmrc" 2>/dev/null || true

    # Native CopperBSD dashboard (Qt6/QML/Kirigami -- no browser, no web
    # server). Built here, on the installed system, against the Qt/KDE libraries
    # that were just downloaded; the source ships on the install medium.
    install_dashboard

    # The media stack, only if it was chosen. The dashboard is native and is
    # NOT part of this; the project's own web dashboard stays disabled.
    if [ "$MEDIA" = "1" ] || [ "$MEDIA" = "true" ]; then
        say "installing the media stack"
        pkg_install python312 py312-pyyaml bash bastille wireguard-tools caddy doas || \
            say "WARNING: some media-stack packages failed (see $LOG)"
        setup_media_stack
    fi

    touch "$DONE"
    say "done -- starting the login screen"
    # rc's service list was built before these packages existed, so start the
    # display stack by hand this once; it starts normally from the next boot.
    for s in dbus seatd sddm; do
        service "$s" onestart >>"$LOG" 2>&1 || true
    done
}

load_rc_config $name
run_rc_command "$1"
