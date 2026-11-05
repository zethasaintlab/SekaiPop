# Native / VM validation protocol

This document is a test protocol, not a certification report. No clean-install, restore-cycle, or graphical-session certification is claimed by the automated container package-plan jobs.

## Fedora 45 reference target

Use a fresh x86_64 Fedora 45 mutable installation with systemd. Install a compatible Hyprland >= 0.55 from a source you independently trust before testing; the SekaiPop installer does not enable COPRs or install a compositor from an unreviewed provider.

Record exact versions:

    cat /etc/os-release
    rpm -q dnf5 qt6-qtbase qt6-qtdeclarative qt6-qtmultimedia quickshell
    Hyprland --version
    qs --version
    qsb --version

If qsb is not installed, that is expected on a fresh Qt < 6.12 system before the installer resolves the Shader Tools dependency.

## Read-only checks

    ./install.sh --plan --profile standard
    ./install.sh --check

Confirm:
- Exact Fedora 45 release policy is selected.
- DNF5 metadata refresh precedes candidate Qt-version resolution during a real install.
- If Qt is < 6.12, qt6-qtshadertools is included; if the effective Qt candidate version cannot be established, the plan fails closed and explains why.
- No COPR, external repository, local RPM, unsigned package, or source build is enabled.
- A compatible existing Hyprland satisfies the capability; otherwise the plan reports the missing mandatory compositor instead of installing an unverified one.
- Existing TuneD PPD, TLP PPD, or power-profiles-daemon providers are preserved and conflicts are not auto-resolved.

## Install and runtime checks

Run the installer interactively:

    ./install.sh --profile standard

After installation:

    ./install.sh --check
    qs -p "$HOME/.config/quickshell/sekaipop" -n -d
    hyprctl configerrors
    busctl --system call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameHasOwner s org.freedesktop.UPower.PowerProfiles
    busctl --system --no-pager introspect org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles

Check the launcher, app search, desktop-entry rescans, widgets, lockscreen, region selector, quick panel, touchpad settings, and clock format. Confirm the Lyrics widget timing controls remain interactive while the global widget lock is enabled. Suspend and resume the machine, then confirm lockscreen clocks refresh.

For Qt < 6.12, confirm the installer compiled every source shader in staging and replaced the .qsb files only after successful compilation. Do not infer success merely from qsb being installed.

## Restore and failure recovery

Before installation, retain a VM snapshot. Test:

    ./install.sh --restore

Verify that the selected Quickshell and Hyprland configuration trees return to their pre-install state, unrelated Quickshell instances remain running, and systemd units return to their original enabled/disabled and active/inactive state.

Native package transactions are intentionally retained after a later deployment failure; the installer does not attempt cross-distribution package downgrades or removals. Verify that the recovery snapshot remains available and inspect the installer log after any injected failure.

## Additional supported baselines

Run equivalent package-plan and install/restore checks on Arch Linux, EndeavourOS, CachyOS, Debian 13 (with official trixie-backports already configured), Ubuntu 26.10 (with Universe already enabled), and Fedora 44. The package-plan CI matrix is not a substitute for native installation, systemd, QML plugin, or graphical validation.

## Result recording

For every test target, record:
- Distribution/release/architecture and image or VM snapshot identifier.
- Package-manager, Qt, Quickshell, Hyprland, and qsb versions.
- Full --plan, installer log, --check, and compositor validation output.
- Whether shader compilation was required and how many shaders compiled.
- Provider state before and after installation.
- Restore result and any remaining manual recovery.
- Pass/fail with the exact failing command and exit status.

Do not mark a release baseline certified until a clean install, runtime session, and restore cycle have all passed on that baseline.