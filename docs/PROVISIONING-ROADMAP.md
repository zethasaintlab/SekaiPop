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

Historical note: the table below preserves the smaller set captured during the initial audit. It is intentionally incomplete and must not be mistaken for the current smoke-build manifest. The complete candidate closure used by the current Fedora 44/45 offline container smoke test is recorded in the later “Version-coherent CMake closure audit” section and in the repository's pinned source-fetch manifest.

| Component | Release | Upstream commit |
|---|---|---|
| Hyprland | v0.57.1 | `acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9` |
| aquamarine | v0.16.0 | `b77d67648336223a6c8fb88844ae316e7b72b574` |
| hyprlang | v0.6.8 | `3a1c1b25b059dae2c6bbc46991562ba1158d125c` |
| hyprcursor | v0.1.13 | `44e91d467bdad8dcf8bbd2ac7cf49972540980a5` |
| hyprutils | v0.14.3 | `0d13d5a624eb093b600d1b2cbe448fb613c86424` |
| hyprgraphics | v0.6.0 | `ade4ef0a887d2740efb9c9af2ddb175633365e1b` |
| hyprwayland-scanner | v0.4.6 | `b8632713a6beaf28b56f2a7b0ab2fb7088dbb404` |

The historical set above is insufficient by itself to build the current upstream chain. Do not use that table as the build input. The later closure audit and pinned source-fetch manifest add Lua, hyprland-protocols, xdg-desktop-portal-hyprland, hyprwire, hyprtoolkit, glaze, and the audited fallback submodules. The smoke manifest is sufficient for the currently tested isolated container build, but it is not yet a production provisioning manifest: source licensing/origin inventory, host runtime integration, transactional installation, and rollback behavior remain separate acceptance gates.

## Version-coherent CMake closure audit

A deeper source audit was performed against one concrete candidate set rather than combining the latest installation guide with unrelated component releases:

- Hyprland **v0.57.1**, commit `acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9`
- xdg-desktop-portal-hyprland **v1.5.0**, commit `d1467fea8d1895cb7835829c2fbb271a0d37760a`
- hyprtoolkit **v0.6.0**, commit `f8cbaf42e1f7fdc9c7565d7be3e935f6d56c7a39`

This is a source-manifest candidate, **not a successful build**. It does not approve a Fedora provider yet.

### Immutable source candidates

| Component | Version | Immutable commit | Why it is in this closure |
|---|---|---|---|
| Hyprland | v0.57.1 | `acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9` | Target compositor |
| aquamarine | v0.16.0 | `b77d67648336223a6c8fb88844ae316e7b72b574` | Hyprland graphics/backend dependency |
| hyprlang | v0.6.8 | `3a1c1b25b059dae2c6bbc46991562ba1158d125c` | Hyprland configuration parser |
| hyprcursor | v0.1.13 | `44e91d467bdad8dcf8bbd2ac7cf49972540980a5` | Cursor library |
| hyprutils | v0.14.3 | `0d13d5a624eb093b600d1b2cbe448fb613c86424` | Shared Hypr* utility library |
| hyprgraphics | v0.6.0 | `ade4ef0a887d2740efb9c9af2ddb175633365e1b` | Graphics helper library |
| hyprwayland-scanner | v0.4.6 | `b8632713a6beaf28b56f2a7b0ab2fb7088dbb404` | Protocol code generator; satisfies both compositor and portal floors |
| hyprland-protocols | v0.8.0 | `044a434ec371f985655389bcef09286b1af3d77c` | Required protocol XML package |
| glaze | v7.2.0 | `b518eec7a22e56ffa238b072c07f47efa7cea97f` | Exact FetchContent tag declared by this Hyprland CMake revision |
| hyprtoolkit | v0.6.0 | `f8cbaf42e1f7fdc9c7565d7be3e935f6d56c7a39` | Required by the v1.5.0 portal share picker |
| hyprwire | 0.3.1 | `a546e42d45e161682f729ebf52375bd4800d7041` | Required by Hyprland v0.57.1's `hyprctl` target; pin is also present in the same Hyprland commit's `flake.lock` |
| xdg-desktop-portal-hyprland | v1.5.0 | `d1467fea8d1895cb7835829c2fbb271a0d37760a` | Hyprland portal backend |
| sdbus-cpp fallback | submodule commit | `b7d85f936d622299ee57966c2b2aefde5e4f3684` | Portal's checked-in fallback; CMake reports version 2.0.0 |
| udis86 fallback | submodule commit | `5336633af70f3917760a6d441ff02d93477b0c86` | Hyprland fallback if system udis86 >= 1.7.2 is unavailable |
| Tracy | optional submodule | `05cceee0df3b8d7c6fa87e9638af311dbabc63cb` | Used only when USE_TRACY is enabled; keep it disabled in a normal release build |

The exact tag-to-commit resolutions above were read from the upstream Git references. Submodule commits were read from the Git trees of the pinned parent commits. The Hyprwire commit is taken from the `hyprwire` node in the pinned Hyprland v0.57.1 `flake.lock`; its `VERSION` file reports 0.3.1.

### Hyprland v0.57.1 configure-time contract

The pinned Hyprland `CMakeLists.txt` requires CMake >= 3.30 and C++26. Its declared pkg-config dependency floors include:

- `xkbcommon >= 1.11.0`, `wayland-server >= 1.22.91`, `wayland-protocols >= 1.49`, and `libinput >= 1.29`
- `uuid`, `cairo`, `pango`, `pangocairo`, `pixman-1`, `xcursor`, `libdrm`, `libeis-1.0`, `gbm`, `gio-2.0`, `re2`, `muparser`, `lcms2`, and `libcanberra`
- OpenGL/GLES3, EGL, glslang, Threads, and pkg-config
- Lua >= 5.5 and < 5.6 (the CMake probe searches for the Lua 5.5 pkg-config names)
- `hyprwayland-scanner >= 0.3.10`
- `aquamarine >= 0.15.0`, `hyprlang >= 0.6.7`, `hyprcursor >= 0.1.7`, `hyprutils >= 0.14.3`, and `hyprgraphics >= 0.5.1`
- `hyprland-protocols >= 0.8.0`
- `sdbus-c++ >= 2.0.0` unless RTKit support is explicitly disabled
- `hyprwire` is a required dependency of the nested `hyprctl/CMakeLists.txt` target (the top-level CMake does not declare it directly). The pinned Hyprwire v0.3.1 CMake contract requires `hyprutils >= 0.9.0` and `libffi`; its nested scanner target additionally requires `pugixml`. The build installs both `libhyprwire`/`hyprwire.pc` and `hyprwire-scanner`, which Hyprland's `hyprctl` build invokes to generate protocol sources.
- XCB, XFixes, ICCCM, Composite, Res, and xcb-errors when XWayland is enabled (the default build path)
- Python 3 for the Lua API stub generation target

If the host does not provide udis86 >= 1.7.2, the build falls back to the pinned udis86 submodule. Tracy is not required when `USE_TRACY` is off. These are distinct from the core mandatory package dependencies and must be represented in a provider-specific build plan.

Hyprland's CMake file uses FetchContent for glaze when no system glaze package is found, with `GIT_TAG v7.2.0`. A production offline build must pre-acquire the exact commit above and either provide it through a controlled CMake source override or install its package config into the isolated prefix. CMake must not be allowed to fetch an unpinned moving branch during configure.

### Portal and picker contract

The pinned portal v1.5.0 CMake file requires Wayland client/protocols >= 1.39, PipeWire >= 1.1.82, libspa, libdrm, uuid, GBM, hyprlang, hyprutils, and `hyprwayland-scanner >= 0.4.2`. If a compatible system `sdbus-c++ >= 2.0.0` package is unavailable, its CMake file falls back to the checked-in sdbus-cpp submodule.

The portal's in-tree `hyprland-share-picker` has a separate CMake target and requires `hyprtoolkit >= 0.6.0`, hyprutils, and libdrm. The pinned hyprtoolkit v0.6.0 itself requires C++23, OpenGL/EGL, scanner >= 0.4.0, aquamarine, hyprgraphics, hyprutils, hyprlang, Wayland client/protocols, pixman, libdrm, GBM, xkbcommon, Pango, Cairo, PangoCairo, iniparser, and Abseil's flat hash map package.

**Important submodule incompatibility:** the portal v1.5.0 Git tree pins its hyprland-protocols submodule at `d260a60f90668bf55dbddb6fa60fba9a3e2e34e9`, whose `VERSION` file says **0.7.1**. The same portal CMake file requires hyprland-protocols >= 0.8.0 and checks for the workspace-image-capture protocol introduced in the newer source. Therefore, its bundled submodule is not a valid fallback for this release. The provider must build/install the separately pinned hyprland-protocols v0.8.0 first and make that package visible through the isolated pkg-config/data paths; it must not silently fall back to the stale submodule.

### Version-coherence correction

The current upstream installation guide's build-order list is a guide to the current upstream tree, not a lockfile for every older release. The initial audit missed a nested dependency: Hyprland v0.57.1's `hyprctl/CMakeLists.txt` explicitly requires `hyprwire` and invokes `hyprwire-scanner`. The pinned Hyprland `flake.lock` independently records Hyprwire commit `a546e42d45e161682f729ebf52375bd4800d7041` (version 0.3.1), so that exact immutable source is now included in the smoke manifest and built before Hyprland. The portal v1.5.0 share-picker separately requires hyprtoolkit; it remains in the closure.

### Remaining provider acceptance gates

**Completed in CI (2026-11-05):** official Fedora 44/45 build dependency acquisition and immutable source-pin verification; offline container builds of the pinned compositor/portal closure; private-prefix installation including the Hyprland systemd user target; pkg-config version checks; ELF dependency checks for the six expected executables; Hyprland version and launcher checks; session desktop-entry and portal metadata presence checks. Both Fedora release jobs emitted `FEDORA_HYPRLAND_SOURCE_BUILD_SMOKE_OK`.

**Not yet proven:** the container smoke does not establish that the source provider is safe or usable on a real host. Before enabling it in the installer, the remaining gates are:

1. Run a clean Fedora 44 and Fedora 45 VM installation test using the real installer, with snapshots and no changes to a daily-driver host.
2. Validate actual graphical login/session startup, Wayland socket and environment, NVIDIA and Mesa paths, Quickshell/QML loading, xdg-desktop-portal selection, screen sharing, D-Bus activation, systemd user integration, logout, suspend/resume, and recovery from a failed launch.
3. Inspect the installed ELF RUNPATH/RPATH for build-tree leakage and prove that private libraries are loaded only through a scoped launcher; do not globally export `LD_LIBRARY_PATH`, add global symlinks, or run `ldconfig` for the private prefix.
4. Implement a versioned provider release layout, staged installation, atomic activation where feasible, and a content-hash ownership manifest.
5. Implement collision refusal and rollback that removes only files created by the transaction and unchanged since creation. Never claim DNF package transactions are reversible.
6. Add upgrade, interrupted-install, partial-uninstall, and rollback tests; verify no unmanaged session, portal, D-Bus, systemd, or library files are overwritten.
7. Complete source license/origin inventory and record build options, compiler/toolchain identity, dependency versions, source commits, and artifact checksums.

The current result therefore advances the candidate from an unbuilt source manifest to a **successful isolated offline source-build smoke test**. It does not approve or enable a Fedora provider in the default installer path.

### Audited upstream source files

- [Hyprland v0.57.1 CMakeLists.txt](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/CMakeLists.txt)
- [Portal v1.5.0 CMakeLists.txt](https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/d1467fea8d1895cb7835829c2fbb271a0d37760a/CMakeLists.txt)
- [Portal v1.5.0 picker CMakeLists.txt](https://github.com/hyprwm/xdg-desktop-portal-hyprland/blob/d1467fea8d1895cb7835829c2fbb271a0d37760a/hyprland-share-picker/CMakeLists.txt)
- [Hyprtoolkit v0.6.0 CMakeLists.txt](https://github.com/hyprwm/hyprtoolkit/blob/f8cbaf42e1f7fdc9c7565d7be3e935f6d56c7a39/CMakeLists.txt)
- [Hyprland-protocols v0.8.0 CMakeLists.txt](https://github.com/hyprwm/hyprland-protocols/blob/044a434ec371f985655389bcef09286b1af3d77c/CMakeLists.txt)
- [Hyprwayland-scanner v0.4.6 CMakeLists.txt](https://github.com/hyprwm/hyprwayland-scanner/blob/b8632713a6beaf28b56f2a7b0ab2fb7088dbb404/CMakeLists.txt)

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


## Distribution package evidence refresh (2026-11-05)

The official package metadata confirms that the native Hyprland baseline is viable on the two APT targets and remains blocked on Fedora:

| Target | Official package evidence | Baseline conclusion |
|---|---|---|
| Debian 13 trixie-backports | `hyprland 0.55.2+ds-1~bpo13+1` | Meets the installer's `>= 0.55.0` version floor; runtime/API validation is still required. [Debian package details](https://packages.debian.org/stable-backports/hyprland) |
| Ubuntu 26.10 Universe | `hyprland 0.56.2+ds-1` | Meets the version floor; runtime/API validation is still required. [Ubuntu package details](https://packages.ubuntu.com/eu/stonking/x11/hyprland) |
| Fedora 44 | Official Fedora package index lists only Fedora 41/42 Hyprland builds | No official Fedora 44 candidate is established. [Fedora package index](https://packages.fedoraproject.org/pkgs/hyprland/hyprland/index.html) |
| Fedora 45 | Official Fedora package index lists only Fedora 41/42 Hyprland builds | No official Fedora 45 candidate is established. [Fedora package index](https://packages.fedoraproject.org/pkgs/hyprland/hyprland/index.html) |

Fedora 44 and 45 both publish stable GCC 16.2.1 packages, satisfying the upstream GCC major-version prerequisite in principle; a clean build still needs an actual C++26 compile/link test against the installed standard library. Fedora also publishes Nix 2.35.3-2 for both releases. Nix installation can therefore use the distribution package, but non-NixOS graphics/session integration remains a separate unvalidated engineering problem. Sources: [Fedora GCC](https://packages.fedoraproject.org/pkgs/gcc/gcc/), [Fedora Nix](https://packages.fedoraproject.org/pkgs/nix/nix/).

These metadata facts narrow the investigation; they do not change the support status. Fedora remains blocked until a complete provider is built and validated. Container package-resolution tests currently stub the Hyprland executable and must not be represented as a Fedora Hyprland installation test.
