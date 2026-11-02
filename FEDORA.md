# Fedora 44

The Fedora profile uses DNF5 and the repositories already configured on the system. It does not enable COPR repositories or build third-party RPMs.

A compatible Hyprland >= 0.55 must already be installed from a source you independently trust. Fedora's reviewed official package baseline does not provide that compositor requirement, so the installer stops rather than silently enabling a personal COPR. Quickshell and Qt runtime packages are resolved from the configured native repositories.

Run ./install.sh --plan --profile standard before installation, then ./install.sh --check after deployment.

Qt >= 6.7 is mandatory. The shipped shaders are built for Qt 6.12; below that version, Qt Shader Tools and qsb are required for a staged shader rebuild. The installer does not modify GPU drivers, Plasma portals, desktop defaults, or service policy beyond explicit confirmations.

The Fedora profile is mock-tested, not VM-certified. Confirm package candidates and QML/plugin paths on a target Fedora 44 installation before deployment.

## Existing capability providers

The standard profile accepts the `ffmpeg` executable as the FFmpeg capability regardless of the RPM package name that owns it; it does not install a second FFmpeg provider when the executable is already present. The Qt base mapping installs the runtime package only, not `qt6-qtbase-devel`.

On Fedora, `tuned-ppd` is accepted as the Power Profiles provider only when its RPM is installed, `tuned-ppd.service` is active, the canonical `org.freedesktop.UPower.PowerProfiles` D-Bus name is owned, and the `/org/freedesktop/UPower/PowerProfiles` object exports that interface. The installer does not enable or replace TuneD, `tuned-ppd`, TLP, or `power-profiles-daemon` automatically when that capability is already provided.
