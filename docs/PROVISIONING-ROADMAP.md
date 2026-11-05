# Full-automatic provisioning: engineering status

Audit snapshot: 2026-11-05. This document records verified upstream constraints for the next provisioning milestone. It is not a claim that source provisioning is already implemented.

## Current automated repository bootstrap

- Debian 13: the installer can create a dedicated Deb822 entry for the official `trixie-backports` archive when missing. Quickshell and Hyprland remain individually suite-targeted.
- Ubuntu 26.10: the installer can create a dedicated Deb822 entry for the official Universe component, release updates, and security updates when missing. It includes official `main` only if no existing main component is configured.
- Both paths use the distribution archive keyring, require confirmation, refresh metadata before candidate resolution, and roll back only newly created source files that remain byte-for-byte unchanged if metadata refresh fails.
- No third-party repository, COPR, PPA, AUR helper, or external package signing key is enabled.

## Fedora Hyprland feasibility

The Fedora profile still has no approved native Hyprland provider. The upstream installation guide documents Fedora through a COPR or manual source build and strongly recommends using distro packages where available because the Hyprland ecosystem has tightly coupled shared-library dependencies.

The current upstream Hyprland release audited for this work is **v0.57.1**, commit:

```text
acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9
```

Its CMake project requires C++26, CMake 3.30, and the following minimum dependency versions:

| Dependency | Minimum |
|---|---:|
| aquamarine | 0.15.0 |
| hyprlang | 0.6.7 |
| hyprcursor | 0.1.7 |
| hyprutils | 0.14.3 |
| hyprgraphics | 0.5.1 |
| xkbcommon | 1.11.0 |
| wayland-server | 1.22.91 |
| wayland-protocols | 1.49 |
| libinput | 1.29 |
| Lua | 5.5.x |
| hyprwayland-scanner | 0.3.10 |

The Hyprland build also requires OpenGL/GLES, glslang, Cairo, Pango, Pixman, libdrm, libeis, GBM, GLib/GIO, re2, muparser, lcms2, libcanberra, and XCB/Xwayland development interfaces unless Xwayland is explicitly disabled.

## Pinned upstream component set under evaluation

The following exact commits were resolved from their upstream release tags. The source provider must verify each checkout against these commit IDs before building.

| Component | Release | Upstream commit |
|---|---|---|
| Hyprland | v0.57.1 | `acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9` |
| aquamarine | v0.16.0 | `b77d67648336223a6c8fb88844ae316e7b72b574` |
| hyprlang | v0.6.8 | `3a1c1b25b059dae2c6bbc46991562ba1158d125c` |
| hyprcursor | v0.1.13 | `44e91d467bdad8dcf8bbd2ac7cf49972540980a5` |
| hyprutils | v0.14.3 | `0d13d5a624eb093b600d1b2cbe448fb613c86424` |
| hyprgraphics | v0.6.0 | `ade4ef0a887d2740efb9c9af2ddb175633365e1b` |
| hyprwayland-scanner | v0.4.6 | `b8632713a6beaf28b56f2a7b0ab2fb7088dbb404` |

Expected build order:

1. hyprutils
2. hyprwayland-scanner
3. hyprlang
4. hyprcursor
5. hyprgraphics
6. aquamarine
7. Hyprland

The stack must be built and installed as one coherent version set. Mixing newly built Hyprland with arbitrary pre-existing Hypr* shared libraries is not an acceptable fallback.

## Fedora release-specific blocker: Lua

Fedora 44's official `lua-devel` is Lua 5.4.8, while Hyprland's current CMake requires Lua 5.5. Fedora 45's official `lua-devel` is Lua 5.5.1.

For Fedora 44, the source provider must supply a **parallel, isolated Lua 5.5** build and a versioned pkg-config module. It must not replace Fedora's system Lua 5.4 ABI.

A verified upstream source artifact is available:

- URL: `https://www.lua.org/ftp/lua-5.5.1.tar.gz`
- SHA-256: `1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce`

Hyprland's CMake module search expression must also be audited to ensure Fedora 44 cannot silently select Lua 5.4 through a permissive fallback module expression.

## Source-provider acceptance requirements

Before enabling the provider in a normal install path:

- Install all build prerequisites from official Fedora repositories only.
- Verify compiler support with a real C++26 compile probe and verify CMake >= 3.30 before building.
- Download only pinned sources; verify every source commit or archive SHA-256 before extraction/build.
- Build the complete Hypr* dependency stack in the order above.
- Use an isolated, versioned installation prefix; never overwrite arbitrary files under `/usr` or `/usr/local`.
- Generate a dedicated session entry and narrowly scoped wrappers so the isolated runtime libraries are loaded without globally changing the user's library environment.
- Record every installed file and source identity in a manifest.
- Make failed builds removable without touching pre-existing files; refuse collisions with unmanaged paths.
- Add mocked failure/rollback tests and a Fedora 44/45 clean-container source-build CI job.
- Keep native VM login, NVIDIA behavior, Quickshell QML loading, portal behavior, suspend/resume, and restore acceptance separate from container build success.

Until these requirements pass, Fedora's Hyprland prerequisite remains explicitly unresolved; the installer must not pretend that the Fedora package plan is a complete clean-system installation.
