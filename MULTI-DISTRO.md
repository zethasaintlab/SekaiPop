# SekaiPop multi-distro installer

## Supported baseline

| Distribution | Package backend | Supported release baseline | Important condition |
|---|---|---|---|
| Arch Linux | pacman | Rolling, x86_64 | No isolated pacman -Sy; a stale sync DB requires explicit --system-upgrade for a full -Syu transaction. |
| EndeavourOS | pacman | Rolling, x86_64 | Uses the Arch package profile. |
| CachyOS | pacman | Rolling, x86_64 | Uses the Arch package profile. |
| Fedora | DNF5 | Fedora 44, x86_64 | Compatible Hyprland >= 0.55 must already exist; no COPR is enabled. |
| Debian | APT | Debian 13 (trixie), x86_64 | Configure official trixie-backports yourself; only Quickshell and Hyprland are suite-targeted. |
| Ubuntu | APT | Ubuntu 26.10 (Stonking Stingray), x86_64 | Universe must already be enabled. |
| Kali Linux | APT | kali-rolling, x86_64 | Canonical Kali sources only; every package candidate is targeted to kali-rolling. |

The installer requires a mutable systemd desktop and x86_64. It detects /etc/os-release by exact ID, VERSION_ID, and (where applicable) VERSION_CODENAME. ID_LIKE is informational only: it does not make Linux Mint or another derivative eligible.

Explicitly excluded: openSUSE, Gentoo, NixOS, Fedora Atomic/ostree variants, other unverified derivatives, and architectures other than x86_64.

### Kali repository and service policy

Kali is accepted only when `ID=kali` and `VERSION_CODENAME=kali-rolling`. Its APT source configuration must contain at least one active binary source and every active binary source must use the canonical `http.kali.org` host with the `kali-rolling` suite. Mixed Debian/Ubuntu suites, `kali-last-snapshot`, and third-party APT sources are rejected before metadata refresh or package transactions. Kali package specifications explicitly target `kali-rolling`; the installer does not add, rewrite, or switch repositories and never performs `apt full-upgrade`.

Kali disables some network services by default, including Bluetooth-related services. SekaiPop may offer to start/enable its required services, but each change remains subject to explicit confirmation. Kali is primarily designed for penetration testing and security auditing; desktop use is an advanced, user-managed configuration. An unverified release is not silently routed to a nearby package backend.

## Runtime requirements

- Hyprland >= 0.55.0 for SekaiPop's Lua configuration/API.
- Qt >= 6.7.0.
- Quickshell with SekaiPop-required QML modules (Hyprland, Wayland, IO, Widgets, PAM, Polkit, Notifications, UPower, PipeWire, MPRIS, and SystemTray).
- Checked-in shader bytecode is built for Qt 6.12. With Qt below 6.12, the native Qt Shader Tools package (qsb) is required for a staged rebuild using the upstream shader script. Qt 6.12+ does not install Shader Tools solely for this purpose.
- Existing GPU drivers are not installed, replaced, or modified.

## Installation

Clone the complete repository, then inspect the plan:

    git clone https://github.com/zethasaintlab/SekaiPop.git
    cd SekaiPop
    ./install.sh --plan
    ./install.sh

The complete checkout is required because the installer deploys the existing sekaipop/ and hypr/ runtime trees. Do not run the installer as root.

## CLI

- ./install.sh --plan or --dry-run: read-only package/deployment plan; no repo refresh or config writes.
- ./install.sh --check: read-only runtime, Qt, QML, Quickshell and plugin check.
- ./install.sh --profile minimal|standard|full: select core, standard, or extended optional scope.
- ./install.sh --deps-only: dependencies/system integration only.
- ./install.sh --no-deps: no package transaction.
- ./install.sh --no-update: skip APT/DNF metadata refresh.
- ./install.sh --no-desktop-layer: omit optional portals/font/desktop convenience packages.
- ./install.sh --hypr merge|full|skip: merge session hook, deploy the complete config, or leave Hyprland untouched.
- ./install.sh --restore: restore the latest configuration snapshot.
- ./install.sh --system-upgrade: Arch-family only; explicitly authorize full pacman -Syu.

--yes accepts ordinary prompts; it does not authorize an unlisted repository or third-party provider.

## Package-source policy

Only repositories already configured by the user are queried. This installer does not add AUR helpers, COPR repositories, PPAs, external RPM/DEB sources, or downloaded build scripts. Consent flags do not whitelist arbitrary sources. Users must review and configure third-party providers independently.

The installer does not alter GPU drivers, kernel modules, Secure Boot, global portal defaults, desktop session environment, or unrelated Quickshell instances. It never kills every qs process. On Fedora, the package planner preserves the installed power-profile provider (TuneD PPD, TLP PPD, or power-profiles-daemon) and will not install a competing provider. If TLP is installed without `tlp-pd`, the optional PowerProfiles integration is reported unavailable rather than forcing a conflicting package transaction.

## Test and certification status

The repository includes mocked routing/CLI tests and integration fixtures. These validate shell logic with controlled command stubs, not native package resolution or an actual graphical desktop. No distribution is claimed as VM-certified. Before general release, validate package resolution and install/restore in native or VM environments for each supported baseline, then test Hyprland Lua, Quickshell QML imports, Qt plugins, shaders, portal behavior, and KDE coexistence.
