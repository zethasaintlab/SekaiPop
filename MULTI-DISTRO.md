# SekaiPop multi-distro installer

## Supported baseline

| Distribution | Package backend | Supported release baseline | Important condition |
|---|---|---|---|
| Arch Linux | pacman | Rolling, x86_64 | No isolated pacman -Sy; a stale sync DB requires explicit --system-upgrade for a full -Syu transaction. |
| EndeavourOS | pacman | Rolling, x86_64 | Uses the Arch package profile. |
| CachyOS | pacman | Rolling, x86_64 | Uses the Arch package profile. |
| Fedora | DNF5 | Fedora 44 and 45, x86_64 | Compatible Hyprland >= 0.55 must already exist; no COPR is enabled. Fedora 45 has a separate release gate and does not assume a stable tuned-ppd candidate. |
| Debian | APT | Debian 13 (trixie), x86_64 | Configure official trixie-backports yourself; only Quickshell and Hyprland are suite-targeted. |
| Ubuntu | APT | Ubuntu 26.10 (Stonking Stingray), x86_64 | Universe must already be enabled. |

The installer requires a mutable systemd desktop and x86_64. It detects /etc/os-release by exact ID, VERSION_ID, and (where applicable) VERSION_CODENAME. ID_LIKE is informational only and never enables an unsupported derivative.

Explicitly excluded: Kali Linux, openSUSE, Gentoo, NixOS, Fedora Atomic/ostree variants, other unverified derivatives, and architectures other than x86_64. An unverified release is not silently routed to a nearby package backend.

## Runtime requirements

- Hyprland >= 0.55.0 for SekaiPop's Lua configuration/API. Hyprland must already be installed from a source the user trusts on Fedora; no third-party repository is enabled by the installer.
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
- ./install.sh --no-update: skip APT/DNF metadata refresh; unresolved candidate versions are reported rather than silently guessed.
- ./install.sh --no-desktop-layer: omit optional portals/font/desktop convenience packages.
- ./install.sh --hypr merge|full|skip: merge session hook, deploy the complete config, or leave Hyprland untouched.
- ./install.sh --restore: restore the latest configuration snapshot.
- ./install.sh --system-upgrade: Arch-family only; explicitly authorize full pacman -Syu.

--yes accepts ordinary prompts; it does not authorize an unlisted repository or third-party provider.

## Package-source policy

Only repositories already configured by the user are queried. This installer does not add AUR helpers, COPR repositories, PPAs, external RPM/DEB sources, or downloaded build scripts. Consent flags do not whitelist arbitrary sources. Users must review and configure third-party providers independently.

The installer does not alter GPU drivers, kernel modules, Secure Boot, global portal defaults, desktop session environment, or unrelated Quickshell instances. It never kills every qs process.

## Deployment transaction and recovery

Configuration deployment, Quickshell activation, and systemd service reconciliation are transactional. Before replacing configuration, the installer creates a snapshot. If required deployment validation, service reconciliation, Quickshell activation, or state-manifest writing fails, it attempts to restore the prior configuration and only the service changes made by the current transaction. A Quickshell instance is managed by its configuration path; unrelated instances are not terminated.

Native package-manager transactions are not rolled back after a later deployment failure. Packages already installed remain installed intentionally; automatic package removal/downgrade across distributions would be unsafe. The recovery snapshot is retained for manual inspection or ./install.sh --restore.

## Test and certification status

Automated shell fixtures and ShellCheck validate installer logic and regression behavior. Package-plan/container CI checks package candidate resolution only; it does not install the desktop or certify a graphical session. No distribution is claimed as clean-install/restore VM-certified until native or VM install/restore, Hyprland Lua, Quickshell QML imports, Qt plugins, shader compilation, portal behavior, and KDE coexistence have been validated.
