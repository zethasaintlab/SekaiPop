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

Kali is accepted only when `ID=kali` and `VERSION_CODENAME=kali-rolling`. Its APT source configuration must contain at least one active binary source and every active `deb` or `deb-src` entry must use exactly `http://http.kali.org/kali` (optionally with the trailing slash) and the `kali-rolling` suite. deb822 `.sources` entries must use `/usr/share/keyrings/kali-archive-keyring.gpg`; legacy `.list` entries may use APT's default trusted keyring but cannot override it. Insecure/trusted repository overrides, malformed or unreadable active source files, custom APT source paths, and external `APT_CONFIG` overrides are rejected. Mixed Debian/Ubuntu suites, `kali-last-snapshot`, and third-party APT sources are rejected before metadata refresh or package transactions. Kali package specifications explicitly target `kali-rolling`; the installer does not add, rewrite, or switch repositories and never performs `apt full-upgrade`.

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

The installer does not alter GPU drivers, kernel modules, Secure Boot, global portal defaults, desktop session environment, or unrelated Quickshell instances. It never kills every qs process. Shader compilation runs in the staged Quickshell tree before replacement. If Hyprland integration or mandatory post-deployment runtime validation fails, the installer restores the pre-deployment configuration snapshot and retains a separate recovery snapshot of the partial state. On Fedora, the package planner preserves the installed power-profile provider (TuneD PPD, TLP PPD, or power-profiles-daemon) and will not install a competing provider. If none is installed, Fedora 44 maps the PowerProfiles capability to its native `tuned-ppd` package. If TLP is installed without `tlp-pd`, the optional PowerProfiles integration is reported unavailable rather than forcing a conflicting package transaction. If multiple provider packages are installed but no provider is active, the service reconciler refuses to choose one automatically. Multiple already-active providers are also left untouched. An active TLP backend without `tlp-pd` prevents automatic TuneD/PPD activation, and an active TLP backend paired with a different active provider is treated as a conflict.

## Fedora 44 host baseline

The Fedora 44 reference host has completed a user-host smoke-validation pass (2026-11-02):

- `./check-deps.sh`: all mandatory runtime checks passed.
- `./install.sh --plan --profile standard`: read-only plan; zero package installations were required on the reference host.
- Hyprland `hyprctl configerrors`: no configuration errors were reported.
- Qt Shader Tools: the temporary compile validation successfully rebuilt 28 GLSL shader sources with the system `qsb`.
- Power profiles: `tuned-ppd` was active and owned `org.freedesktop.UPower.PowerProfiles`; its expected D-Bus object/interface was present.
- Quickshell was running through the path-scoped SekaiPop configuration instance.

This is the compatibility baseline for Fedora 44 changes. Preserve the Fedora package-manager route, DNF5 behavior, existing TuneD PPD provider selection, and path-scoped Quickshell lifecycle. Any later change touching these areas must pass the Fedora regression fixtures and must not install or activate a competing PowerProfiles provider.

This host evidence does **not** certify clean installation on a fresh Fedora machine, rollback under an actual failure, or a fresh VM restore cycle.

## Test and certification status

The repository includes mocked routing/CLI tests and integration fixtures. In addition, pull requests run read-only package-plan resolution against native package-manager metadata in disposable Arch, Fedora 44, Debian 13, Ubuntu 26.10, and Kali rolling containers. Container package metadata is refreshed before creating a dedicated unprivileged `sekaipop-ci` account; the installer plan itself runs as that account, matching the production non-root execution model. This checks candidate availability and release/suite routing; it does not install the packages or certify systemd, Hyprland, Quickshell, restore behavior, or a graphical desktop. EndeavourOS and CachyOS use the Arch package profile and are routing-tested, but are not separate container images. No distribution is claimed as VM-certified. Before general release, validate actual install/restore in native or VM environments for each supported baseline, then test Hyprland Lua, Quickshell QML imports, Qt plugins, shaders, portal behavior, and KDE coexistence.

## Transaction boundaries and package retention

Configuration deployment and systemd service reconciliation are journaled separately from native package-manager transactions.

- Before replacing Quickshell/Hyprland configuration, the installer snapshots the selected configuration trees.
- A service that SekaiPop enables/starts is recorded with its original enablement/active state. If a later configuration, activation, or manifest step fails, the installer attempts to reverse only those service changes in reverse order. Pre-existing active services are not stopped.
- After successful deployment and state-manifest activation, the service journal is committed.
- Native package transactions are **not rolled back** when a later desktop deployment step fails. Packages successfully installed by pacman, DNF5, or APT remain installed; automatic rollback is intentionally limited to SekaiPop configuration, Quickshell instance lifecycle, and service changes that the current transaction made. This avoids attempting an unsafe cross-distribution package downgrade/removal.
- If systemd refuses a rollback action, the installer reports the incomplete service rollback. Inspect the affected units with `systemctl status` or `systemctl --user status` and use the retained configuration recovery snapshot as needed.
- The installer state manifest is written to a same-filesystem temporary file with user-only permissions, then atomically renamed over the prior manifest. A failed write/rename does not truncate the previous successful manifest.

## Native and VM certification status

No distribution is currently VM-certified. CI container package resolution and the Fedora 44 reference-host smoke baseline are separate evidence categories; neither proves a clean native install or restore cycle.

Use [NATIVE-VM-VALIDATION.md](NATIVE-VM-VALIDATION.md) as the single source of truth for the supported-distro test matrix, step-by-step install/restore procedure, rollback fault injection, and evidence required before a VM certification claim.
