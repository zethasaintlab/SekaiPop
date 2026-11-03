# Fedora 44

The Fedora profile uses DNF5 and the repositories already configured on the system. It does not enable COPR repositories or build third-party RPMs.

A compatible Hyprland >= 0.55 must already be installed from a source you independently trust. Fedora's reviewed official package baseline does not provide that compositor requirement, so the installer stops rather than silently enabling a personal COPR. Quickshell and Qt runtime packages are resolved from the configured native repositories.

Run ./install.sh --plan --profile standard before installation, then ./install.sh --check after deployment.

Qt >= 6.7 is mandatory. The shipped shaders are built for Qt 6.12; below that version, Qt Shader Tools and qsb are required for a staged shader rebuild. The installer does not modify GPU drivers, Plasma portals, desktop defaults, or service policy beyond explicit confirmations.

The Fedora 44 reference host has completed a smoke-validation pass (dependency checks, Hyprland config validation, shader compilation, Quickshell path-scoped runtime, and TuneD PPD D-Bus ownership). This is host evidence, not a clean-install or restore VM certification. Package candidates and QML/plugin paths must still be validated on fresh native/VM installations.

## Existing capability providers

The standard profile accepts the `ffmpeg` executable as the FFmpeg capability regardless of the RPM package name that owns it; it does not install a second FFmpeg provider when the executable is already present. The Qt base mapping installs the runtime package only, not `qt6-qtbase-devel`.

On Fedora, the runtime PowerProfiles capability is satisfied only when the canonical `org.freedesktop.UPower.PowerProfiles` D-Bus name is owned and the `/org/freedesktop/UPower/PowerProfiles` object exports that interface. An installed provider package by itself is not treated as an active runtime API. For a fresh Fedora 44 installation, the native `tuned-ppd` package is the default mapped provider; an already active TuneD PPD, TLP PPD, or `power-profiles-daemon` service takes precedence over package order. An installed-but-inactive provider may be offered for activation with confirmation. Multiple active providers, multiple inactive provider packages, an active TLP backend without `tlp-pd`, and conflicting active TLP plus TuneD/PPD stacks are left untouched and reported rather than automatically resolved.
