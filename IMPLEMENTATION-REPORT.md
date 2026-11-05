# Implementation report

## Integrated architecture

- One root installer lifecycle and shared CLI.
- Exact /etc/os-release distribution/release allowlist; ID_LIKE is not a router.
- Native package adapters: pacman, DNF5, and APT.
- Separate package maps for Arch-family, Fedora, Debian, and Ubuntu.
- Logical requirement catalog and minimal/standard/full profiles.
- Qt Shader Tools is selected only when the effective Qt version is below 6.12.
- Quickshell QML/plugin verification, staged shader rebuild, systemd integration, and Hyprland merge/full/skip integration.
- Scoped Quickshell process management, configuration snapshots, restore, and first-install absence tracking.
- No GPU-driver mutation or automatic third-party repository activation.

## Release baseline

| Family | Accepted baseline | Constraints |
|---|---|---|
| Arch Linux | Rolling, x86_64 | pacman -Syu only with explicit authorization; never isolated -Sy. |
| EndeavourOS | Rolling, x86_64 | Arch profile. |
| CachyOS | Rolling, x86_64 | Arch profile. |
| Fedora | 44 and 45, x86_64 | DNF5; compatible Hyprland must already exist; no COPR is enabled. |
| Debian | 13 trixie, x86_64 | Official trixie-backports (main) must already be configured; Quickshell/Hyprland are individually suite-targeted. |
| Ubuntu | 26.10 stonking, x86_64 | Official Universe must already be enabled for release, updates, and security. |

openSUSE, Gentoo, NixOS, Kali, Fedora Atomic/ostree variants, unverified derivatives, and non-x86_64 architectures are excluded.

## Validation boundary

The checked-in GitHub Actions workflow runs ShellCheck, shell/runtime regression fixtures, launcher JavaScript tests, integration/service/runtime tests, a static dependency inventory, and native package-manager candidate resolution in Arch, Fedora 44/45, Debian 13, and Ubuntu 26.10 containers. It also runs a pinned Fedora 44/45 Hyprland plus xdg-desktop-portal-hyprland source-build smoke: immutable source inputs and official build dependencies are acquired first, then compilation and installation run with container networking disabled into an isolated private prefix, followed by install-manifest, ELF, session-entry, portal, and systemd-target checks. This demonstrates container build feasibility only; the installer does not yet deploy or activate that private prefix as a Fedora host provider. None of these CI checks establishes clean native installation, VM certification, graphical-session compatibility, NVIDIA/Mesa behavior, suspend/resume, upgrade, rollback, or restore acceptance. See NATIVE-VM-VALIDATION.md for the required certification protocol.

## Source references

- SekaiPop runtime: https://github.com/Blapples/SekaiPop/tree/036afe49b6ee40bf18c01efdb585f000422c7c21
- End-4 architecture reference: https://github.com/end-4/dots-hyprland/tree/2f2a376fdb2ad738bf55f693dd0b474b64bb0ab8
- ii-p3drovfx Fedora packaging reference: https://github.com/P3DROVFX/ii-p3drovfx/tree/1cbc59302c1aacdf77b4871ff028fed36cb40cb5

SekaiPop remains the authoritative runtime source. The reference repositories inform architectural separation only; their package providers and system-modification behavior are not copied wholesale.
