# Fedora 44 and Fedora 45

The Fedora profile uses DNF5 and repositories already configured on the system. It does not enable COPR repositories or build third-party RPMs.

A compatible Hyprland >= 0.55 must already be installed from a source you independently trust. The installer does not install Hyprland from an unreviewed provider and does not enable a personal COPR. Quickshell and Qt runtime packages are resolved from configured native repositories.

Fedora 44 is the existing host-smoke baseline. Fedora 45 is explicitly recognized by its own release gate, but it is not yet VM-certified. Run ./install.sh --plan --profile standard before installation, then ./install.sh --check after deployment.

Qt >= 6.7 is mandatory. The static QML inventory includes QtQuick, QtQuick.Controls.impl, QtQuick.Effects, QtQuick.Layouts, QtQuick.Shapes, QtQml.Models, Qt.labs.folderlistmodel, and QtMultimedia. Fedora resolves the Qt Quick/QML imports through qt6-qtdeclarative and QtMultimedia through qt6-qtmultimedia; the installer does not request Qt development headers merely to load these runtime modules. The shipped shaders are built for Qt 6.12; below that version, Qt Shader Tools and qsb are required for a staged shader rebuild. The installer refreshes DNF metadata before resolving candidate Qt versions. With --no-update or a read-only plan, an unknown effective Qt version is reported as an unresolved mandatory dependency rather than silently omitting Shader Tools.

The installer does not modify GPU drivers, Plasma portals, desktop defaults, or service policy beyond explicit confirmations. Existing PowerProfiles providers are detected before any package is proposed. Fedora 45 does not request tuned-ppd from testing updates as a default package candidate; an already installed and active provider may still satisfy the runtime capability.

## Existing capability providers

The standard profile accepts the ffmpeg executable as the FFmpeg capability regardless of the RPM package name that owns it; it does not install a second FFmpeg provider when the executable is already present. This checks executable availability only, not codec coverage; Fedora's free FFmpeg build has a restricted codec set, and the installer does not replace it with an unverified third-party codec provider. The Qt base mapping installs the runtime package only, not qt6-qtbase-devel.

PowerProfiles is considered satisfied only when the canonical org.freedesktop.UPower.PowerProfiles D-Bus name is owned and the /org/freedesktop/UPower/PowerProfiles object exports that interface. The installer inspects TuneD PPD, TLP PPD, and power-profiles-daemon before proposing a provider. It does not install or activate a competing provider when a conflicting or ambiguous provider state is detected.

Fedora 45 package metadata currently exposes tuned-ppd in testing updates rather than a verified stable candidate, so the Fedora 45 profile will not request it automatically. A provider already installed on the host can still be detected and preserved.
