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
