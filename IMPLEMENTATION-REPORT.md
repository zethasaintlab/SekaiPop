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
| Fedora | 44, x86_64 | DNF5; compatible Hyprland must already exist. |
| Debian | 13 trixie, x86_64 | Official trixie-backports must be configured. |
| Ubuntu | 26.10 stonking, x86_64 | Universe must already be enabled. |

openSUSE, Gentoo, NixOS, Kali, Fedora Atomic/ostree variants, unverified derivatives, and non-x86_64 architectures are excluded.

## Validation boundary

The local overlay validation reported 47 routing/CLI assertions, 14 integration scenarios, and Bash syntax checks passed. Those tests use mocked package-manager and desktop commands. They do not establish live package transactions, VM certification, or GUI compatibility. ShellCheck/Lua syntax checks and native distro/graphical tests remain release gates. The checked-in GitHub Actions workflow reruns the repository smoke and integration tests.

## Source references

- SekaiPop runtime: https://github.com/Blapples/SekaiPop/tree/036afe49b6ee40bf18c01efdb585f000422c7c21
- End-4 architecture reference: https://github.com/end-4/dots-hyprland/tree/2f2a376fdb2ad738bf55f693dd0b474b64bb0ab8
- ii-p3drovfx Fedora packaging reference: https://github.com/P3DROVFX/ii-p3drovfx/tree/1cbc59302c1aacdf77b4871ff028fed36cb40cb5

SekaiPop remains the authoritative runtime source. The reference repositories inform architectural separation only; their package providers and system-modification behavior are not copied wholesale.
