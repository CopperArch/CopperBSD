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

# Build tools out again -- but only if nothing else needs them: pkg delete also
# removes every package that depends on what it deletes, and GNOME depends on
# meson -> ninja, so a blanket "pkg delete cmake ninja" uninstalled the gnome
# metapackage and Nautilus right after installing them.
remove_build_tools() {
    for _t in cmake ninja; do
        pkg info -e "$_t" || continue
        [ -n "$(pkg query '%rn' "$_t")" ] && continue
        env ASSUME_ALWAYS_YES=YES pkg delete -y "$_t" >>"$LOG" 2>&1 || true
    done
}
DONE=/var/db/copperbsd-firstboot.done
NET_WAIT_TRIES=60

# The media-stack installer prints the generated qBittorrent password into
# this log; keep it root-only.
( umask 077; touch "$LOG" ); chmod 600 "$LOG"

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
    env ASSUME_ALWAYS_YES=YES pkg install -y "$@" >>"$LOG" 2>&1 && return 0
    # pkg refuses the whole list when one name is missing from the repo (it
    # happened: brightnessctl, mangowc), which left no desktop at all. Retry
    # one at a time so everything that does exist still gets installed.
    say "a package in this set failed -- retrying one at a time"
    _rc=0
    for _p in "$@"; do
        env ASSUME_ALWAYS_YES=YES pkg install -y "$_p" >>"$LOG" 2>&1 ||
            { say "  could not install $_p"; _rc=1; }
    done
    return $_rc
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
    # qt6-webengine draws the terminal dock (Claude Code and the other panes).
    # Installed on its own: it is by far the largest of these, and without it
    # the dashboard still builds -- only the dock is missing.
    pkg_install qt6-webengine || \
        say "WARNING: qt6-webengine failed to install; the dashboard is built without its terminal dock (see $LOG)"
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
    remove_build_tools
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
# Vendor/device lines of display-class PCI devices only. Grepping all of
# pciconf matched the AMD chipset of any AMD-CPU machine as an AMD GPU.
display_pci()
{
    pciconf -lv 2>/dev/null | awk '/^[^ \t]/ { v = ""; d = "" }
        /^[ \t]+vendor/ { v = $0 } /^[ \t]+device/ { d = $0 }
        /^[ \t]+class[ \t]*= display/ { print v " " d }'
}

configure_display()
{
    if display_pci | grep -qiE 'AMD|ATI|Radeon|Intel'; then
        say "GPU with a KMS driver detected -- leaving Xorg on autodetect"
    elif [ "$(sysctl -n machdep.bootmethod 2>/dev/null)" = UEFI ]; then
        # UEFI: only scfb can drive the GOP framebuffer -- vesa needs the
        # BIOS and fails with "V_BIOS address 0x0 out of range", which left
        # the login screen dead. scfb cannot switch modes, so the loader is
        # asked for 1080p (as on the live medium) and X uses whatever it got.
        say "no KMS GPU, UEFI -- configuring the UEFI framebuffer display (scfb)"
        grep -q '^efi_max_resolution=' /boot/loader.conf 2>/dev/null || \
            printf 'efi_max_resolution="1080p"\n' >> /boot/loader.conf
        mkdir -p /usr/local/etc/X11/xorg.conf.d
        cat > /usr/local/etc/X11/xorg.conf.d/20-copperbsd-fb.conf <<'XORG'
Section "Device"
    Identifier "Card0"
    Driver "scfb"
EndSection
XORG
    else
        say "no KMS GPU, BIOS -- configuring a 1920x1080 VESA display"
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

# -- keyboard -----------------------------------------------------------------
# rc.conf's keymap= covers only the text console. X and the Wayland compositors
# need XKB names (the console's "uk" is "gb" there); the installer works those
# out (copperarch-install.sh xkb_from_keymap) and passes them in firstboot.conf.
# Without this the login screen and every desktop stayed on US.
configure_keyboard()
{
    : "${XKB_LAYOUT:=us}" "${XKB_VARIANT:=}"
    say "keyboard: console keymap ${KEYMAP:-us} -> XKB layout $XKB_LAYOUT${XKB_VARIANT:+ ($XKB_VARIANT)}"
    mkdir -p /usr/local/etc/X11/xorg.conf.d /usr/local/etc/copperbsd
    {
        printf 'Section "InputClass"\n    Identifier "copperbsd keyboard"\n    MatchIsKeyboard "on"\n'
        printf '    Option "XkbLayout" "%s"\n' "$XKB_LAYOUT"
        [ -n "$XKB_VARIANT" ] && printf '    Option "XkbVariant" "%s"\n' "$XKB_VARIANT"
        printf 'EndSection\n'
    } > /usr/local/etc/X11/xorg.conf.d/00-copperbsd-keyboard.conf
    # libxkbcommon reads these when a compositor names no layout (MangoWC)
    printf 'XKB_DEFAULT_LAYOUT=%s\nXKB_DEFAULT_VARIANT=%s\nexport XKB_DEFAULT_LAYOUT XKB_DEFAULT_VARIANT\n' \
        "$XKB_LAYOUT" "$XKB_VARIANT" > /usr/local/etc/copperbsd/keyboard.sh
}

# -- login screen ---------------------------------------------------------------
# Pre-select the chosen desktop in SDDM (it reads /var/lib/sddm/state.conf, not
# ~/.dmrc, so GNOME installs offered "GNOME Classic" first), give the greeter a
# real theme when KDE's breeze is not installed, and set its cursor: SDDM runs
# xsetroot from a PATH without /usr/local/bin and failed ("Could not setup
# default cursor"), so the pointer only appeared over a widget.
configure_login_screen()
{
    X=/usr/local/share/xsessions; W=/usr/local/share/wayland-sessions
    case "$DESKTOP" in
        gnome)   SESS=$X/gnome-xorg.desktop ;;
        xfce)    SESS=$X/xfce.desktop ;;
        niri)    SESS=$W/niri.desktop ;;
        mangowc) SESS=$W/mangowc.desktop ;;
        *)       SESS=$X/plasmax11.desktop ;;
    esac
    if [ -f "$SESS" ]; then
        install -d -o sddm -g sddm /var/lib/sddm 2>/dev/null || install -d /var/lib/sddm
        printf '[Last]\nSession=%s\nUser=%s\n' "$SESS" "$USERNAME" > /var/lib/sddm/state.conf
        chown sddm:sddm /var/lib/sddm/state.conf 2>/dev/null || true
    else
        say "WARNING: session file $SESS not found; the login screen keeps its own default"
    fi
    _b=$(basename "$SESS" .desktop)
    printf '[Desktop]\nSession=%s\n' "$_b" > "/home/$USERNAME/.dmrc"
    chown "$USERNAME" "/home/$USERNAME/.dmrc" 2>/dev/null || true

    install -d /usr/local/libexec /usr/local/etc/sddm.conf.d
    cat > /usr/local/libexec/copperbsd-xsetup <<'XSETUP'
#!/bin/sh
# SDDM display setup: default pointer, then the stock Xsetup.
/usr/local/bin/xsetroot -cursor_name left_ptr 2>/dev/null
[ -x /usr/local/share/sddm/scripts/Xsetup ] && exec /usr/local/share/sddm/scripts/Xsetup "$@"
exit 0
XSETUP
    chmod 755 /usr/local/libexec/copperbsd-xsetup
    {
        printf '[X11]\nDisplayCommand=/usr/local/libexec/copperbsd-xsetup\n'
        [ -d /usr/local/share/sddm/themes/breeze ] || printf '[Theme]\nCurrent=maldives\n'
    } > /usr/local/etc/sddm.conf.d/10-copperbsd.conf
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
        drm-kmod dejavu pipewire wireplumber xkbcomp setxkbmap xsetroot indexinfo xmlcatmgr || say "WARNING: some desktop packages failed (see $LOG)"

    for kv in $DESKTOP_RC; do sysrc "$kv" >>"$LOG" 2>&1; done
    configure_display
    configure_keyboard
    if display_pci | grep -qiE 'AMD|ATI|Radeon'; then
        sysrc kld_list+="amdgpu" >>"$LOG" 2>&1
        kldload -n amdgpu >>"$LOG" 2>&1 || true   # this boot too: sddm starts below
    elif display_pci | grep -qi 'Intel'; then
        sysrc kld_list+="i915kms" >>"$LOG" 2>&1
        kldload -n i915kms >>"$LOG" 2>&1 || true   # this boot too: sddm starts below
    fi

    # Session wrappers/configs for the tiling Wayland desktops -- only for the
    # ones that were installed (their entries were in every login menu before,
    # e.g. Niri and MangoWC offered on a GNOME-only machine).
    D="$SHARE/desktop"
    install -d /usr/local/share/wayland-sessions /usr/local/etc/niri /usr/local/etc/xdg/quickshell
    for w in niri mangowc; do
        case "$DESKTOP" in "$w"|all) ;; *) continue ;; esac
        [ -f "$D/wayland-sessions/$w.desktop" ] && cp "$D/wayland-sessions/$w.desktop" /usr/local/share/wayland-sessions/
        [ -f "$D/bin/$w-session" ] && install -m 755 "$D/bin/$w-session" /usr/local/bin/
    done
    [ -f "$D/etc/niri/config.kdl" ] && cp "$D/etc/niri/config.kdl" /usr/local/etc/niri/ &&
        sed -i '' "s/layout \"us\"/layout \"$XKB_LAYOUT\"${XKB_VARIANT:+; variant \"$XKB_VARIANT\"}/" \
            /usr/local/etc/niri/config.kdl
    [ -f "$D/etc/xdg/quickshell/shell.qml" ] &&
        cp "$D/etc/xdg/quickshell/shell.qml" /usr/local/etc/xdg/quickshell/

    # Niri's swaybg wallpaper: the dashboard's background (it pointed at a file
    # nothing installed, so Niri started on a blank background).
    [ -f "$SHARE/dashboard/assets/background.jpg" ] &&
        cp "$SHARE/dashboard/assets/background.jpg" "$SHARE/wallpaper.jpg"

    configure_login_screen
    # Native CopperBSD dashboard (Qt6/QML/Kirigami; QtWebEngine only for the
    # terminal dock). Built here, on the installed system, against the Qt/KDE libraries
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
