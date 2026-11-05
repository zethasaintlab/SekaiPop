# CI validation record — Run #809

Date: 2026-11-05  
Repository: `zethasaintlab/SekaiPop`  
PR: [#14](https://github.com/zethasaintlab/SekaiPop/pull/14)  
Validated commit: `c4d9c1b1313be69cf8dd6a18291a81a195ef04aa`  
Workflow: [Run #809](https://github.com/zethasaintlab/SekaiPop/actions/runs/42033552552)

## Result

**All 8 of 8 jobs passed.** The workflow completed successfully on the exact PR head listed above.

| Job | Result |
|---|---|
| Shell tests | Success |
| Arch Linux package resolution (container) | Success |
| Fedora 44 package resolution (container) | Success |
| Fedora 45 package resolution (container) | Success |
| Debian 13 package resolution (container) | Success |
| Ubuntu 26.10 package resolution (container) | Success |
| Fedora 44 pinned Hyprland offline source-build smoke | Success |
| Fedora 45 pinned Hyprland offline source-build smoke | Success |

## Shell-test evidence

The shell job completed ShellCheck and the installer regression/integration fixtures. Its reported totals were:

- 97 smoke assertions passed, 0 failed.
- 8 systemd service assertions passed, 0 failed.
- APT repository validation fixtures passed, including rejection of Deb822 `trusted=yes`, legacy `trusted=yes`, and legacy `allow-weak=yes`.
- Production planner fixtures confirmed that a failed native APT transaction aborts dependency provisioning and that unmet mandatory requirements after a nominally successful transaction are rejected.
- Private-prefix validation fixtures passed.

The log contains expected negative-path fixture output (including simulated non-zero package-manager exits). Those lines are test stimuli, not workflow failures. The workflow job itself concluded successfully.

## Fedora offline build evidence

Both Fedora jobs completed the following sequence:

1. Build an official Fedora container image and acquire the pinned source/dependency inputs.
2. Verify immutable source pins and source artifact checksums.
3. Run the build container with Docker networking disabled.
4. Compile and install the pinned Hyprland + xdg-desktop-portal-hyprland closure into `/opt/sekaipop/prefix`.
5. Validate each CMake install manifest against the private prefix, including symlink-resolved paths.
6. Verify pinned pkg-config versions and ELF runtime dependencies for the expected executables.
7. Emit `FEDORA_HYPRLAND_SOURCE_BUILD_SMOKE_OK`.

Both release logs confirm installation of:

`/opt/sekaipop/prefix/lib64/systemd/user/hyprland-session.target`

Both report `PRIVATE_PREFIX_VALIDATION_OK` with **644 manifest entries**. The ELF validation passed for:

- `Hyprland`
- `start-hyprland`
- `hyprland-share-picker`
- `hyprctl`
- `hyprwire-scanner`
- `xdg-desktop-portal-hyprland`

The pinned pkg-config versions were checked for hyprland-protocols, hyprwayland-scanner, hyprutils, hyprgraphics, hyprlang, hyprcursor, aquamarine, hyprtoolkit, hyprwire, and Lua 5.5.

## What this result proves

- The tested pinned source closure can be acquired and built in Fedora 44 and Fedora 45 container environments.
- The actual build phase succeeds after network access is disabled.
- The resulting CMake install manifests are confined to the private prefix under the validator's lexical and symlink-resolved path checks.
- The required Hyprland systemd user target is installed under that prefix.
- The listed executable ELF runtime dependency checks pass in the smoke environment.
- The latest APT source parser and dependency-failure regression fixtures pass.

## What this result does not prove

This is a container feasibility smoke test, **not a production Fedora host provider** and not native desktop certification. It does not prove:

- deployment of the private prefix onto a host;
- a scoped production launcher or runtime library search-path policy;
- display-manager session discovery and graphical login;
- D-Bus and xdg-desktop-portal activation on a real host;
- screen sharing, NVIDIA/Mesa behavior, Quickshell QML/plugin compatibility;
- suspend/resume, upgrade, interruption recovery, uninstall, or transactional rollback;
- a clean native installation on any supported distribution.

The installer must continue to require a compatible trusted Hyprland already present on Fedora hosts. The source-build smoke must not be interpreted as enabling automatic Fedora Hyprland provisioning.

## Merge/release status

Run #809 validates commit `c4d9c1b1313be69cf8dd6a18291a81a195ef04aa`; it does not by itself satisfy the outstanding native VM and Fedora host-provider gates. PR #14 therefore remains Draft and unmerged pending final documentation/diff review and an explicit acceptance decision.

See also:

- [Fedora provider decision record](FEDORA-HYPRLAND-PROVIDER-DECISION.md)
- [Provisioning roadmap](PROVISIONING-ROADMAP.md)
- [Native/VM validation protocol](../NATIVE-VM-VALIDATION.md)
