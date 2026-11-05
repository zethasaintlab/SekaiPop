# Fedora Hyprland provider decision record

Date: 2026-11-05
Status: investigation; no provider enabled

## Decision

Do not silently install Hyprland from a COPR, third-party RPM, unpinned source checkout, or a Nix profile as a side effect of the normal Fedora package transaction.

The currently supported SekaiPop Fedora target is Fedora 44/45. The official Fedora package mappings do not currently provide a verified compatible Hyprland + Hypr* dependency closure for these releases. The installer must continue to report Hyprland as a missing mandatory capability instead of presenting an incomplete package plan as a complete installation.

## Nix alternative evaluated

Hyprland's current installation guide explicitly recommends using distribution packages where available because its ecosystem has tightly coupled dependencies. It also documents Nix as a way to avoid shared-library version conflicts across distributions.

The NixOS Wiki describes installing `nixpkgs#hyprland` on non-NixOS hosts, but also documents an additional `nixGL` wrapper requirement for graphics-driver integration. This is not a turnkey drop-in for a conventional Fedora desktop:
- The upstream instructions require installing/configuring Nix first.
- The non-NixOS graphics path may need nixGL, which is a separate community project and must itself be pinned and audited.
- Session registration, display-manager discovery, portal integration, GPU driver passthrough, and privilege/capability behavior must be validated on the host.
- A Nix profile alone does not automatically provision the rest of SekaiPop's system services and host integrations.
- Enabling third-party substituters or trusting their signing keys would introduce another trust boundary.

Fedora announced an official `nix` package in its updates repositories, with Fedora 44 as an approved Change. This makes Nix installation more feasible without piping a remote shell script, but does not resolve the non-NixOS graphics/session integration requirements.

### Nix provider conclusion

Nix is a viable **opt-in experimental provider candidate**, not an approved default provider yet. A future implementation would need:
1. Install Nix only from the host distribution's official repository.
2. Pin an immutable Nixpkgs revision in a checked-in flake lock.
3. Use only the official Nixpkgs Hyprland package initially; no arbitrary Hyprland Cachix or community substituter.
4. Audit whether the pinned package works against Fedora's host graphics stack without nixGL. If it does not, stop rather than silently installing an unreviewed third-party graphics shim.
5. Generate and test a dedicated Wayland session entry and portal configuration.
6. Prove rollback by switching back to the previous Nix profile generation without deleting unrelated Nix packages.
7. Test Intel, AMD, and NVIDIA separately; NVIDIA is a hard acceptance gate, not an assumed success.
8. Keep the provider disabled by default until clean Fedora 44 and 45 VM tests pass.

## Source-build version-coherence update

A source-level CMake audit now exists in [PROVISIONING-ROADMAP.md](PROVISIONING-ROADMAP.md#version-coherent-cmake-closure-audit) for a concrete candidate pair: Hyprland v0.57.1, xdg-desktop-portal-hyprland v1.5.0, and hyprtoolkit v0.6.0. It records exact commits, the CMake dependency floors, pinned glaze FetchContent, udis86/sdbus-cpp fallbacks, and the portal's stale hyprland-protocols submodule (0.7.1 despite a >= 0.8.0 requirement).

This matters because the generic current upstream installation guide is not a version lockfile. The first CMake audit missed a nested target dependency: Hyprland v0.57.1's `hyprctl/CMakeLists.txt` requires `hyprwire` and invokes `hyprwire-scanner`. The pinned Hyprland `flake.lock` records Hyprwire commit `a546e42d45e161682f729ebf52375bd4800d7041` (version 0.3.1). The Fedora offline smoke manifest now acquires that exact commit and builds it against pinned hyprutils before configuring Hyprland. Hyprtoolkit remains required by the portal share-picker. Do not combine a generic current build order with arbitrary older component pins. The detailed audit is still incomplete and does not approve or implement a Fedora provider.

## Source-build alternative

A first-party pinned source builder remains possible but is a large maintenance commitment. Hyprland's current upstream build order includes Lua, hyprland-protocols, hyprwayland-scanner, hyprutils, hyprgraphics, hyprlang, hyprcursor, aquamarine, xdg-desktop-portal-hyprland, hyprwire, hyprtoolkit, and Hyprland.

A partial build of only the seven previously pinned components is not sufficient. The complete dependency closure, including all non-Hypr dependencies and any CMake FetchContent/submodule sources, must be pinned and acquired before building. The build must then work offline. No system SONAME symlinks or global LD_LIBRARY_PATH changes are acceptable.

## Current implementation behavior

Until one of the providers passes the acceptance gates:
- Fedora's package map keeps `hyprland` and `portal-hyprland` unmapped.
- The planner must list missing Hyprland as a mandatory requirement.
- The installer must not continue into deployment/activation as though the machine has a complete compositor baseline.
- Existing user-installed Hyprland may satisfy the runtime capability only if its version and required API are compatible; this does not make a clean installation automatic.

## References

- Hyprland installation guide: https://wiki.hypr.land/getting-started/installation/
- NixOS Wiki, Hyprland on non-NixOS: https://wiki.nixos.org/wiki/Hyprland
- Fedora Nix package announcement: https://discourse.nixos.org/t/nix-package-manager-now-available-in-fedora/73932
- NixOS Wiki, Nix installation: https://wiki.nixos.org/wiki/Nix_Installation_Guide
- Nixpkgs Hyprland module and session/portal integration: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/programs/wayland/hyprland.nix


## Updated official Fedora package evidence (2026-11-05)

The live Fedora Packages metadata now makes the provider gap precise:

- The official `hyprland` package page lists only Fedora 41 and Fedora 42 builds (0.44.1 and 0.45.2 respectively), and marks the package maintainer as orphaned. It does not list Fedora 44 or Fedora 45 builds. This is not a valid official provider for the supported releases: [Fedora Packages — hyprland](https://packages.fedoraproject.org/pkgs/hyprland/hyprland/index.html).
- The compiler requirement is no longer a Fedora 44/45 blocker: Fedora Packages lists GCC 16.2.1 as stable on both Fedora 44 and Fedora 45. The source provider must still verify the actual C++26 compiler **and standard-library** compile/link probe in each clean build environment: [Fedora Packages — gcc](https://packages.fedoraproject.org/pkgs/gcc/gcc/).
- Nix is available as a distribution-packaged option on both releases (2.35.3-2.fc44 and 2.35.3-2.fc45). This removes the need to install Nix through an upstream shell installer, but it does not solve the non-NixOS graphics, session, portal, or NVIDIA integration questions: [Fedora Packages — nix](https://packages.fedoraproject.org/pkgs/nix/nix/).

The source-build candidate is therefore more feasible than a compiler-only assessment might suggest, but still not approved. The remaining hard blockers are the complete official package/version closure, Fedora 44's isolated Lua 5.5 requirement, hermetic acquisition/build of every pinned source and submodule, and real session/graphics/portal validation. Do not enable a source provider until every acceptance gate in the roadmap is evidenced.


## Upstream Hyprland Nix flake audit (2026-11-05)

The pinned Hyprland v0.57.1 source commit `acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9` contains a substantially more complete Nix provider than a generic `nixpkgs#hyprland` lookup suggests. Its checked-in `flake.lock` locks Nixpkgs to `0bb2eedc20e4739f29e8045034f2828ad7054f8f` with a NAR hash and pins the Hypr* dependency graph, portal, toolkit, systems input, and pre-commit hook input. The `packages` output exposes both `hyprland` and `xdg-desktop-portal-hyprland`.

The pinned `nix/default.nix` derivation explicitly uses `gcc16Stdenv`, `lua5_5`, `sdbus-cpp_2`, XWayland dependencies, and the Hyprland GUI utilities. It builds with systemd support when the target platform provides systemd, sets `NO_UWSM` accordingly, and declares the Hyprland session as a provided session. This is a coherent upstream-maintained build closure and avoids Fedora 44's host Lua 5.4 mismatch by using the Nix store's Lua 5.5 dependency.

However, the non-NixOS graphics requirement is explicit in the same pinned upstream source: [`start/src/helpers/Nix.cpp`](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/start/src/helpers/Nix.cpp) checks whether Hyprland was built with Nix and, on a non-NixOS host without `/run/opengl-driver`, refuses to launch unless `nixGL` is available on PATH. The source even points to `github:guibou/nixGL --impure`. This is not an optional cosmetic wrapper: it is a launch prerequisite for the documented non-NixOS graphics path.

### Updated Nix assessment

- **Positive:** official Fedora RPMs can install Nix itself on both supported releases; the upstream Hyprland flake provides a locked Hyprland + portal build graph, GCC 16, and Lua 5.5; the upstream package contains a Wayland session desktop file.
- **Negative:** a working non-NixOS launch requires a separately reviewed and pinned nixGL provider unless the host has a compatible Nix OpenGL driver environment. The upstream NixOS module cannot be applied directly to Fedora. The system Wayland-session entry must be exposed to the display manager, and the portal's D-Bus service/portal metadata must be made visible to the host's xdg-desktop-portal. NVIDIA and other GPU paths remain unvalidated.
- **Security:** the upstream lockfile pins every flake input by immutable revision and NAR hash, but it also contains auxiliary inputs such as `nix-systems/default-linux` and `cachix/git-hooks.nix`. A provider must audit which inputs are actually evaluated/fetched for the production package outputs, retain the lockfile, reject lockfile mutation during install, and use only trusted Nix substituters with verified signatures. Do not add unpinned `--override-input` values.
- **Decision:** Nix is now the strongest experimental Fedora candidate for a pinned compositor/portal build, but remains **opt-in only** until nixGL provenance/pinning, display-manager registration, portal activation, GPU coverage, upgrade, and rollback are validated. It is not enabled by default and does not yet satisfy the clean Fedora acceptance gate.

Primary source evidence:
- [Hyprland v0.57.1 flake.nix](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/flake.nix)
- [Hyprland v0.57.1 flake.lock](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/flake.lock)
- [Hyprland v0.57.1 Nix derivation](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/nix/default.nix)
- [Hyprland v0.57.1 Nix overlay](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/nix/overlays.nix)
- [Hyprland v0.57.1 Nix runtime guard](https://github.com/hyprwm/Hyprland/blob/acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9/start/src/helpers/Nix.cpp)
- [Hyprland Nix-on-any-distro guide](https://wiki.hypr.land/nix/hyprland-on-any-distro-using-nix/)


## Fedora 44/45 official build-dependency inventory (2026-11-05)

A read-only DNF5 capability inventory was run inside disposable official Fedora 44 and 45 container images. The command ran after `dnf5 makecache --refresh`, queried only enabled distribution repositories, and did not install any build dependencies or add repositories. Evidence is in [CI run #72597360](https://github.com/zethasaintlab/SekaiPop/actions/runs/41972597360), commit `fed655ae1393f696fe5f586b74a9fec94f6fc6d4`.

The queried pkg-config providers were present on both releases for the audited CMake closure, including:

- C++/graphics/runtime: `xkbcommon`, Wayland client/server, `wayland-protocols`, `libinput`, `uuid`, Cairo, Pango/PangoCairo, Pixman, Xcursor, libdrm, libEIS, GBM, GIO, re2, muparser, lcms2, libcanberra, GL/EGL/GLESv2, and glslang.
- XWayland: XCB, render, XFixes, Composite, ICCCM, RES, and xcb-errors.
- Portal and toolkit: `libpipewire-0.3`, `libspa-0.2`, libseat, libudev, libdisplay-info, hwdata, iniparser, Abseil flat hash map, libjpeg, libwebp, libmagic, libpng, librsvg, and sdbus-c++.

Notable candidate versions observed in enabled official repositories:

| Requirement | Fedora 44 candidate | Fedora 45 candidate | Pinned minimum |
|---|---:|---:|---:|
| xkbcommon | 1.13.1 | 1.13.1 | 1.11.0 |
| wayland-protocols | 1.49 | 1.49 | 1.49 |
| libinput | 1.31.3 | 1.32.0 | 1.29.0 |
| libpipewire-0.3 | 1.6.11 | 1.6.11 | 1.1.82 |
| libseat | 0.9.3 | 0.9.3 | 0.8.0 |
| sdbus-c++ | 2.2.1 | 2.3.1 | 2.0.0 |
| GCC C++ | 16.2.1 | 16.2.1 | 16 |
| CMake | 4.3.0 | 4.3.0 | 3.30 |

The only confirmed release-specific toolchain gap in this inventory is Lua 5.5:

- Fedora 44's official `lua-devel` candidate is 5.4.8; no `lua5.5-devel` package candidate exists. The provider must build Lua 5.5.1 from the already pinned, SHA256-verified upstream archive into an isolated prefix and prove CMake links to that exact library.
- Fedora 45's official `lua-devel` candidate is 5.5.1 and satisfies the pinned Hyprland requirement.

The inventory is intentionally read-only and reports package availability, not a successful build. It does not validate every transitive source/build action, the exact selected candidate after package installation, runtime ELF closure, display-manager session discovery, portal activation, NVIDIA behavior, or rollback. The follow-up [CI run #72803525](https://github.com/zethasaintlab/SekaiPop/actions/runs/41972803525) also passed 6/6 jobs and confirmed that Fedora 44/45 provide the `wayland-scanner` pkg-config module through `wayland-devel` and an official `xorg-x11-server-Xwayland` package candidate. The next inventory revision additionally checks the scanner's `pugixml` dependency, hyprcursor's `libzip` and `tomlplusplus` dependencies, and the optional system `udis86` provider; that run is pending and must be inspected before treating this inventory as final.

### Consequence for provider selection

The source-build route is now a credible default-provider candidate: the tested official Fedora repositories appear to supply the native C++26, Wayland, graphics, PipeWire, portal, and toolkit prerequisites at or above the pinned floors. Fedora 44's Lua 5.5 gap is isolated and has a pinned upstream source artifact. This is materially stronger evidence than the previous package-name-only assessment.

The next gate is a clean Fedora 44 and 45 **offline-after-acquisition** source build of the complete pinned closure, including all CMake FetchContent/submodule inputs, followed by ELF and session/portal inspection. No source provider is enabled in the installer until those tests pass.


### Transitive scanner/cursor dependency audit

The next read-only inventory, [CI run #72961919](https://github.com/zethasaintlab/SekaiPop/actions/runs/41972961919), passed **6/6 jobs** on commit `8d73713a5fd304bc48b30fe6ae116ea0c20a285b`. It additionally confirmed official Fedora providers for the source-level dependencies that were previously absent from the inventory:

| CMake module | Fedora 44 | Fedora 45 |
|---|---|---|
| `pugixml` (hyprwayland-scanner) | 1.16 | 1.16 |
| `libzip` (hyprcursor) | 1.11.4 | 1.12.1 |
| `tomlplusplus` (hyprcursor) | 3.4.0 | 3.4.0 |

The package candidates were resolved from the enabled Fedora repositories only. The only missing named package in the full inventory remains `lua5.5-devel`; this is expected to be supplied by the verified Lua 5.5.1 source artifact in an isolated prefix, not by replacing Fedora 44's Lua 5.4 ABI. Fedora 45's official `lua-devel` candidate is already 5.5.1. The system `udis86` provider check is part of the next inventory revision; if unavailable or below 1.7.2, the pinned Hyprland submodule commit `5336633af70f3917760a6d441ff02d93477b0c86` is the explicit offline fallback.

This makes the official Fedora native dependency closure appear complete for the selected source set, subject to the final `udis86` check and a real offline build. It is still not build or desktop validation.


### Complete native capability inventory result

The expanded inventory at [CI run #73015392](https://github.com/zethasaintlab/SekaiPop/actions/runs/41973015392), commit `3376097086b55d9c2d3f1d5eae0f2b2f78577936`, passed **6/6 jobs**. It queried the full set of audited pkg-config modules from the pinned Hyprland, aquamarine, hyprgraphics, hyprcursor, hyprtoolkit, portal, and scanner CMake files, plus build tools and the XWayland runtime package.

Results for both Fedora 44 and Fedora 45:

- All queried official native pkg-config providers were found, including `pugixml`, `libzip`, `tomlplusplus`, `wayland-scanner`, `libpipewire-0.3`, `libspa-0.2`, `libseat`, `libdisplay-info`, `hwdata`, `absl_flat_hash_map`, `sdbus-c++`, and all graphics/XCB interfaces.
- The official `xorg-x11-server-Xwayland` package candidate exists on both releases.
- The only missing pkg-config provider is `udis86`; the pinned Hyprland CMake explicitly falls back to its checked-in submodule when no suitable system library exists. The parent Git tree pins that submodule at `5336633af70f3917760a6d441ff02d93477b0c86`, so this gap is covered by an immutable source input.
- The only missing named development package is `lua5.5-devel`. Fedora 44 has `lua-devel 5.4.8`; Fedora 45 has `lua-devel 5.5.1`. For a single reproducible provider, the proposed smoke build will build the same SHA256-verified Lua 5.5.1 archive into a private prefix on both releases, avoiding any ambiguity about which Lua library CMake selects.

No third-party repository or community package source was needed to satisfy the audited native dependency closure. This makes a fully pinned source-build provider technically viable on both Fedora releases, subject to the next decisive test: acquire all pinned inputs, disable network access, and compile/install the entire compositor + portal closure in a clean container. The inventory still does not prove that build succeeds or that the graphical session works.


### First offline build attempt: submodule staging correction

The first Fedora 44/45 offline build attempts ([run #73422135](https://github.com/zethasaintlab/SekaiPop/actions/runs/41973422135)) compiled and installed Lua 5.5.1, hyprland-protocols, hyprwayland-scanner, hyprutils, hyprgraphics, hyprlang, hyprcursor, aquamarine, and hyprtoolkit on both releases. They stopped before portal/Hyprland configuration because the source checkout contained an empty Git submodule directory and the smoke script treated any pre-existing path as a conflict.

The smoke script now verifies that the submodule path is empty and populates it from the already verified udis86 commit using `git archive`; it refuses to overwrite any non-empty path. The follow-up run must still prove the portal and Hyprland builds, ELF closure, and session metadata.
