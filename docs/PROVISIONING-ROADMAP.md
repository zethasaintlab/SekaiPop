# Full-automatic provisioning: engineering status

Audit snapshot: 2026-11-05. This document records verified upstream constraints for the next provisioning milestone. It is not a claim that source provisioning is already implemented.

## Current automated repository bootstrap

- Debian 13: the installer can create a dedicated Deb822 entry for the official `trixie-backports` archive when missing. Quickshell and Hyprland remain individually suite-targeted.
- Ubuntu 26.10: the installer can create a dedicated Deb822 entry for the official Universe component, release updates, and security updates when missing. It includes official `main` only if no existing main component is configured.
- Both paths use the distribution archive keyring, require confirmation, refresh metadata before candidate resolution, and roll back only newly created source files that remain byte-for-byte unchanged if metadata refresh fails.
- No third-party repository, COPR, PPA, AUR helper, or external package signing key is enabled.

## Fedora Hyprland feasibility

The alternative-provider investigation is recorded in [FEDORA-HYPRLAND-PROVIDER-DECISION.md](FEDORA-HYPRLAND-PROVIDER-DECISION.md). Nix is documented as an opt-in candidate, not enabled by default: non-NixOS graphics-driver integration, session registration, portal behavior, and NVIDIA remain unverified.

The Fedora profile still has no approved native Hyprland provider. The current upstream installation guide documents manual source builds and explicitly warns against symlinking incompatible shared-library versions. It also states that Hyprland uses C++26 and requires GCC >= 16 or Clang >= 19. Fedora 44/45 have a sufficiently recent compiler toolchain, but that alone does not make the full Hyprland stack available.

The upstream installation guide was updated on 2026-11-03. Its current documented source-build order is:

1. Lua
2. hyprland-protocols
3. hyprwayland-scanner
4. hyprutils
5. hyprgraphics
6. hyprlang
7. hyprcursor
8. aquamarine
9. xdg-desktop-portal-hyprland
10. hyprwire
11. hyprtoolkit
12. Hyprland

The upstream dependency list also includes `glaze`, `xcb-util-errors`, `libdisplay-info`, `libliftoff`, `tomlplusplus`, `re2`, `muparser`, `hyprland-qtutils`, and the relevant Wayland/XCB/graphics development interfaces. The source provider must derive the exact dependency graph from the pinned source manifests and CMake files, not treat this list as a complete package transaction.

Upstream explicitly warns that symbolic-linking different shared-library versions together can cause memory bugs and crashes. Therefore, the previous idea of building only a partial Hypr* library subset and mixing it with arbitrary pre-installed libraries is rejected. A provider must either build and install a complete, internally consistent dependency closure or use a fully compatible official package set.

## Fedora release facts and constraints

- Fedora 45's official toolchain change set includes GCC 16.2 and Lua 5.5.
- Fedora 44's official CMake package is newer than the upstream CMake 3.30 minimum; Fedora 44's CMake changelog also records the FindLua fix for Lua 5.5.
- Fedora 44's standard Lua development package remains Lua 5.4.x in the audited package snapshot. Hyprland must not accidentally configure against Lua 5.4 merely because a permissive CMake fallback accepts it. Fedora 44 therefore still needs an isolated Lua 5.5 build or an equally reliable version-specific provider.
- Fedora's official `hyprlang`, `hyprutils`, `hyprgraphics`, and `hyprland-protocols` packages exist, but the audited Fedora 44/45 versions are older than the minimums in the current upstream Hyprland source set. Their existence is not evidence that they are ABI/API compatible.
- Fedora's official `hyprland` package metadata currently advertises older Fedora releases and does not establish a compatible Fedora 44/45 candidate. The installer must resolve candidates from the live configured DNF metadata and verify versions rather than infer availability from package names.

## Pinned upstream component set under evaluation

The following exact commits were resolved from upstream release tags in the initial audit. They are a partial pin set, not a complete source-build manifest.

| Component | Release | Upstream commit |
|---|---|---|
| Hyprland | v0.57.1 | `acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9` |
| aquamarine | v0.16.0 | `b77d67648336223a6c8fb88844ae316e7b72b574` |
| hyprlang | v0.6.8 | `3a1c1b25b059dae2c6bbc46991562ba1158d125c` |
| hyprcursor | v0.1.13 | `44e91d467bdad8dcf8bbd2ac7cf49972540980a5` |
| hyprutils | v0.14.3 | `0d13d5a624eb093b600d1b2cbe448fb613c86424` |
| hyprgraphics | v0.6.0 | `ade4ef0a887d2740efb9c9af2ddb175633365e1b` |
| hyprwayland-scanner | v0.4.6 | `b8632713a6beaf28b56f2a7b0ab2fb7088dbb404` |

The set above is insufficient to build the current upstream chain: it does not yet pin Lua, hyprland-protocols, xdg-desktop-portal-hyprland, hyprwire, hyprtoolkit, glaze, or all transitive build inputs. Do not start a production build from this partial list. Complete the manifest by resolving release tags to immutable commits, auditing each source's submodules and CMake FetchContent behavior, and recording licenses and source origins.

## Lua source artifact

A verified upstream Lua source artifact is available:

- URL: `https://www.lua.org/ftp/lua-5.5.1.tar.gz`
- SHA-256: `1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce`

For Fedora 44, the provider must install Lua 5.5 in a parallel, versioned prefix and expose a dedicated `lua5.5.pc` module. It must not replace Fedora's system Lua 5.4 ABI. Configure-time validation must prove that Hyprland links against the intended Lua 5.5 library.

## Source-provider acceptance requirements

Before enabling a provider in a normal install path:

- Install build prerequisites from official Fedora repositories only.
- Verify the C++26 compiler and standard library with a real compile/link probe; verify CMake, Meson, Ninja, and all native dependency versions before building.
- Download only immutable, fully pinned sources. Verify every git commit or source archive checksum before any configure/build step.
- Audit and disable unpinned CMake FetchContent, submodule, and network fallback paths. A build must succeed with network access disabled after source acquisition.
- Build the complete upstream dependency chain in its documented order, including the Lua and portal/toolkit components required by the selected Hyprland revision.
- Use a versioned, isolated installation prefix. Never overwrite arbitrary files under `/usr` or `/usr/local`, and never symlink different SONAME versions to satisfy a dependency.
- Generate a dedicated Wayland session entry and narrowly scoped runtime launch wrapper so isolated libraries are loaded without globally changing the user's library environment.
- Record every installed file, package identity, source commit, build option, and checksum in a manifest.
- Refuse collisions with unmanaged paths. Failed installation must roll back only files created by that transaction and must preserve any files modified after creation.
- Add mocked failure/rollback tests and clean Fedora 44/45 container builds with network disabled after source acquisition.
- Keep native VM login, NVIDIA behavior, Quickshell QML loading, portal/screen-sharing behavior, suspend/resume, upgrades, and restore acceptance separate from container build success.

Until these requirements pass, Fedora's Hyprland prerequisite remains explicitly unresolved. The installer must not claim that a successful DNF package-resolution plan constitutes a complete clean-system installation.

## Authoritative references

- Hyprland installation guide: https://wiki.hypr.land/getting-started/installation/
- Hyprland source: https://github.com/hyprwm/Hyprland
- Fedora GCC 16 toolchain change: https://fedoraproject.org/wiki/Releases/45/ChangeSet
- Fedora 44 CMake package/changelog: https://packages.fedoraproject.org/pkgs/cmake/cmake/fedora-44.html
- Fedora Hyprland package status: https://packages.fedoraproject.org/pkgs/hyprland/hyprland/index.html
