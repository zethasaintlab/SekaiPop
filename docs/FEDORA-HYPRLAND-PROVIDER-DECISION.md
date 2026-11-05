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

This matters because the generic current upstream installation guide is not a version lockfile. In the exact CMake files inspected for that candidate pair, hyprwire is not declared as a dependency; hyprtoolkit is required by the portal share-picker. Do not combine a generic current build order with arbitrary older component pins. The detailed audit is still incomplete and does not approve or implement a Fedora provider.

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
