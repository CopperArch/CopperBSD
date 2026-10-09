# CopperArch graphical installer (Qt/QML)

A native, Anaconda/Calamares-style installer for the CopperArch Media OS. It
presents a modern graphical wizard and drives FreeBSD's own `bsdinstall` ZFS
backend — it does **not** reimplement partitioning.

## Build

Needs Qt 6.8+ (`qt6-base`, `qt6-declarative`, `qt6-quickcontrols2`), CMake, Ninja.
On FreeBSD:

```sh
pkg install -y qt6-base qt6-declarative qt6-quickcontrols2 cmake ninja pkgconf
cmake -S installer/gui -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
cmake --install build          # → /usr/local/bin/copperarch-installer
install -m 0755 installer/gui/backend/copperarch-install.sh \
    /usr/local/libexec/copperarch-install.sh
```

(The release build in `dist/` does all of this for you inside the image.)

## Structure

```
CMakeLists.txt              Qt 6.8 project; one QML module "CopperArch"
src/main.cpp               QGuiApplication + loadFromModule("CopperArch","Main")
src/InstallerBackend.*     QObject: runs the driver via QProcess, streams
                             PROGRESS/STEP/LOG/DONE → QML; sends answers on stdin
src/DiskModel.*            QAbstractListModel of detected disks (from --list-disks)
qml/Main.qml               the wizard shell (step rail + StackView + nav)
qml/Theme.qml              design-token singleton (CopperArch palette)
qml/pages/*.qml            Welcome · Locale · Keyboard · Disk · Account ·
                             Summary · Install · Finish
backend/copperarch-install.sh
                           privileged driver: --list-disks / --keymaps /
                             --timezones / --install / --reboot
```

## The GUI ↔ backend contract

The app calls `copperarch-install.sh --install` and writes the collected answers
as `key=value` lines on stdin:

```
disk=ada0
zfsVdev=stripe
swapGiB=8
hostname=copperarch-media
username=copper
fullname=…
password=…            # never placed on argv or in a file
rootPassword=…
timezone=Europe/London
keymap=us
enableMediaStack=true
```

The driver replies one token per stdout line, which `InstallerBackend` parses:

```
STEP <label>        current phase (shown above the progress bar)
PROGRESS <0..100>   overall percent
LOG <text>          line for the log pane
DONE ok | DONE fail <message>
```

Disk/keymap/timezone enumeration return their data on stdout (`--list-disks`
emits JSON; the others newline-separated), so the lists always match what the
running system — and `bsdinstall` — actually accept.

## Safety

- `InstallerBackend.liveMode` and the driver both require `/etc/copperarch-live`
  (present only on the ISO) before any disk write, so running the binary on an
  installed system can't wipe it. Override for testing with `COPPERARCH_FORCE=1`.
- Passwords travel only on the driver's stdin — never argv (`ps`) or a file.
