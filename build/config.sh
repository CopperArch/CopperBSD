#!/bin/sh
# config.sh — single source of truth for the CopperBSD build. Sourced by every
# build/test script. Override any value via the environment.
set -u

# ── identity ────────────────────────────────────────────────────────────────
: "${DISTRO_NAME:=CopperBSD}"
: "${DISTRO_VERSION:=15.1}"
: "${DISTRO_ARCH:=amd64}"
: "${ISO_LABEL:=COPPERBSD}"
: "${ISO_NAME:=CopperBSD-${DISTRO_VERSION}-${DISTRO_ARCH}.iso}"

# ── pinned FreeBSD base (see freebsd/SOURCE.md) ─────────────────────────────
: "${FREEBSD_BRANCH:=releng/15.1}"
: "${FREEBSD_COMMIT:=e38a7085f3a8ecd317c947591fe42b5ca9ab317b}"
# git.FreeBSD.org is authoritative; the GitHub mirror is the documented fallback
# for environments that can't reach it.
: "${FREEBSD_GIT_OFFICIAL:=https://git.FreeBSD.org/src.git}"
: "${FREEBSD_GIT_MIRROR:=https://github.com/freebsd/freebsd-src.git}"

# ── build host paths (inside the FreeBSD builder) ───────────────────────────
: "${SRCDIR:=/usr/src}"               # full FreeBSD source (fetched at pinned commit)
: "${WORKDIR:=/scratch/copperbsd}"    # scratch for world/kernel + live root
: "${LIVE_ROOT:=${WORKDIR}/live}"     # the live filesystem we pack into the ISO
: "${OUTDIR:=${COPPERBSD_OUTDIR:-build/output}}"

# ── live-medium package set (kept small on purpose) ──────────────────────────
# The live ISO ships ONLY enough to boot and run the graphical installer.
# Every desktop (KDE/GNOME/XFCE/Niri/MangoWC) and the media-stack tooling
# (bastille/caddy/wireguard-tools/ttyd) are installed on demand -- the
# installer backend pkg-installs the chosen desktop onto the TARGET at
# install time (desktop_pkgs() in packages/desktops.conf), and the
# media-stack is pkg-installed on first boot only if the user opted in (see
# installer/backend/copperarch-install.sh). Baking those into the live medium
# was the bug that made the live root 14GB+ (kde + xorg metaports pulled in
# ~900 packages); verified via `pkg rquery` that sddm's real deps are tiny
# (consolekit2, dbus, libXau, libglvnd, libxcb, xauth/xmessage/xrdb/xsetroot)
# -- it does NOT need the "xorg" or "kde" metaports. The live session is
# `cage` (x11-wm/cage, a ~3-package Wayland kiosk compositor: wlroots020,
# wayland, libxkbcommon) running the installer fullscreen, not a full Plasma
# session (see overlays/.../wayland-sessions/copperarch-installer.desktop).
: "${PKG_SET:=sddm cage seatd drm-kmod \
    xorg-server xf86-video-scfb xf86-video-vesa xf86-input-libinput dejavu doas \
    setxkbmap \
    qt6-base qt6-declarative}"

# Build-only tools: needed to compile the installer inside the live-root
# chroot, deleted from the image before packing (in-vm-build.sh step 4.5) so
# they never ship on the medium at all.
: "${BUILD_ONLY_PKGS:=cmake ninja pkgconf git}"

# ── repo root (the CopperBSD checkout) ──────────────────────────────────────
# Resolved relative to this file so it works wherever the repo lives.
_cfg_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || echo .)
case "$_cfg_dir" in
    */build) : "${COPPERBSD_ROOT:=$(dirname "$_cfg_dir")}" ;;
    *)       : "${COPPERBSD_ROOT:=$_cfg_dir}" ;;
esac
export COPPERBSD_ROOT
