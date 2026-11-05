# Fedora Hyprland host-provider design

Date: 2026-11-05  
Status: **proposal only — not implemented, enabled, or approved for normal installation**  
Scope: Fedora 44/45, x86_64, mutable systemd systems.

## 1. Verified baseline and limits

The pinned Hyprland v0.57.1 + xdg-desktop-portal-hyprland v1.5.0 source closure builds in Fedora 44 and 45 containers after source acquisition, with networking disabled during compilation and installation. The smoke validates the private-prefix manifest, Hyprland user session target, selected ELF dependencies, version/launcher, session desktop entry, and portal metadata.

- Main commit `227acef2c5ec8a500d873d1f24d8237055d3323d`, [CI #822](https://github.com/zethasaintlab/SekaiPop/actions/runs/42051125891): 8/8 jobs passed.
- Documentation PR head `c01098f3d313c20b3b1fc06971ec3c3e8229bd68`, [CI #827](https://github.com/zethasaintlab/SekaiPop/actions/runs/42054824503): 8/8 jobs passed.
- Both Fedora build logs emitted `FEDORA_HYPRLAND_SOURCE_BUILD_SMOKE_OK`.

This is container build-feasibility evidence only. It does not prove display-manager discovery, native graphical login, portal activation, Mesa/NVIDIA compatibility, suspend/resume, upgrade, rollback, or restore. The installer must continue to treat Fedora Hyprland as an unsatisfied mandatory capability unless the user already has a compatible trusted compositor.

## 2. Non-negotiable safety properties

1. The default Fedora install path remains unchanged until all native acceptance gates pass.
2. Existing user-installed Hyprland is never overwritten, downgraded, shadowed, or removed.
3. The provider is opt-in and registered as a separate session; the original session remains available for recovery.
4. Build dependencies are isolated; do not install hundreds of development RPMs onto the host as an incidental side effect.
5. No COPR, PPA, AUR helper, unpinned branch, arbitrary binary release, or unverified signing key.
6. No global `LD_LIBRARY_PATH`, global SONAME symlink, `ldconfig` entry, or overwrite of RPM-owned files.
7. Install, activation, upgrade, and removal are separate transactions.
8. Rollback removes only provider-owned paths whose content still matches the recorded ownership manifest. DNF package transactions are not claimed to be reversible.
9. Unsupported Fedora variants, architectures, and releases fail closed.

## 3. Proposed build pipeline

### Isolation

Preferred candidate: rootless Podman with an official Fedora base image matching the target release. This is a design candidate, not a verified runtime requirement.

- Build Fedora 44 artifacts in Fedora 44 and Fedora 45 artifacts in Fedora 45; no cross-release builds.
- Use only enabled official Fedora repositories inside the build container.
- Acquire immutable Git commits and the SHA256-verified Lua 5.5.1 archive before compilation.
- Compile/install with container networking disabled after acquisition.
- Do not bind-mount host system directories. The only writable host mount is a dedicated staging-output directory.
- Do not run privileged. Verify rootless user namespaces and SELinux volume labeling.
- If Podman/rootless operation is unavailable, stop with instructions; never fall back to installing build dependencies on the host.

### Reproducibility gap

The source-build workflow now resolves the official Fedora 44/45 tag to a `sha256` image digest, passes that immutable reference to the Dockerfile, and refuses tag-only builds. The new `BUILD-PROVENANCE` record captures the selected image digest, Fedora release/architecture, enabled DNF repository metadata, installed RPM NEVRAs, compiler/build-tool versions, every pinned source commit, and the Lua archive SHA256. The record is emitted only after source acquisition and before compilation; the offline build log prints it on successful completion.

This closes the **per-run base-image identity and build-input traceability gap**, but does not yet make builds bit-for-bit reproducible. The digest is resolved from the moving official tag on each run rather than selected from a committed release lock, and DNF repositories still resolve live RPM versions. Before a host release:
- Commit reviewed Fedora 44/45 base-image digests and update them deliberately.
- Snapshot or lock enabled repository metadata and exact RPM NEVRAs/checksums; fail if resolution differs from the reviewed lock.
- Retain the provenance record as a CI artifact or durable release input, not only as transient job output.
- Verify compiler, C++ standard library, CMake, Ninja, Meson, pkg-config, Lua, and all native dependency versions against the lock.
- Keep source commits and archive hashes in one machine-readable manifest consumed by fetch and build steps.

### Versioned artifact layout

Candidate:

```text
/opt/sekaipop/providers/hyprland/
  releases/0.57.1-acc1aa0bfd4b/
    bin/ lib/ lib64/ libexec/ share/
    BUILD-PROVENANCE
    INSTALL-MANIFEST
  current -> releases/0.57.1-acc1aa0bfd4b
```

- Each release is immutable after publication.
- Build with the final absolute release path as `CMAKE_INSTALL_PREFIX`, because the current smoke embeds the prefix in ELF RPATH/RUNPATH.
- Build in the container, export the full prefix to a host staging directory, and validate before changing host paths.
- Staging and final release must share a filesystem for atomic rename.
- Refuse pre-existing release paths, symlinked provider roots, and unexpected owner/permission state.
- The active pointer is the only mutable provider selector. Replace it atomically and only if it is a symlink owned by SekaiPop.
- Retain the previous release until the user confirms the new session works.

## 4. Runtime and desktop integration

### Scoped launcher

A separate session entry must call a SekaiPop-owned launcher, not resolve Hyprland from an arbitrary PATH.

The launcher must resolve the active release canonically, reject targets outside the provider root, add only the release's `bin` and `share` paths to the session-local `PATH` and `XDG_DATA_DIRS`, preserve the caller's environment, and exec the versioned Hyprland binary. It must not modify shell startup files, global environment files, or system-wide systemd configuration.

Avoid `LD_LIBRARY_PATH` if validated per-ELF RUNPATH/RPATH is sufficient. The current smoke checks six executables with `ldd` after unsetting `LD_LIBRARY_PATH`; production validation must cover every installed ELF executable and shared library, unresolved relocations, private-library RUNPATH containment, and build/source path leakage. If a scoped loader variable proves unavoidable, it must affect only the compositor process tree and be tested for leakage into child desktop processes.

### Display-manager session

Register a unique entry such as `sekaipop-hyprland.desktop`; never replace the existing `Hyprland.desktop`.

- Verify the actual session search path for the supported display manager before selecting the install destination.
- GDM is the first required target. SDDM is supported only after separate testing.
- Refuse any existing file at the chosen path, even if its label looks similar.
- Use an absolute launcher path, validate desktop-file syntax and Exec resolution, stage the file, then publish atomically.
- Preserve the original session and its exact prior state. Do not symlink into RPM-owned directories as a workaround if the display manager cannot discover the entry.

### Portal and D-Bus

Audit the exact generated `.portal`, D-Bus service, and systemd user-unit files from the pinned portal source. Prove which lookup paths are honored by the running D-Bus session and portal daemon; do not assume `XDG_DATA_DIRS` also registers a systemd user unit.

Verify that the Hyprland backend is selected only for the intended desktop, coexists with GTK/other backends, and supports ScreenCast, Screenshot, and FileChooser independently. Do not mask, disable, or replace another backend. Use D-Bus activation through verified service metadata where possible; add a user unit only if the upstream activation contract and native tests require it. Any per-user portal config must be backed up, collision-checked, and restored exactly.

## 5. Transaction and ownership model

A root-owned machine-readable manifest (mode 0600 or stricter) should record schema/provider version, transaction ID, Fedora release/architecture, image digest, repo metadata identity, RPM NEVRAs/checksums, source commits/archive hashes, toolchain/build flags, final prefix, every installed relative path, file type/mode/owner, hashes, integration-file hashes, and previous active release.

Never parse the manifest with `source` or `eval`. Validate schema, path roots, file types, and hashes before destructive actions.

Install sequence:
1. Detect exact Fedora release, architecture, systemd, display manager, and rootless Podman capability.
2. Validate prerequisites read-only.
3. Acquire sources and record provenance.
4. Build in isolation with network disabled.
5. Export to a unique staging directory; validate all files, ELF dependencies, RUNPATH, session metadata, portal metadata, and manifest.
6. Refuse symlinks, unmanaged collisions, unexpected ownership, or existing provider state.
7. Publish the immutable release and verify hashes after publication.
8. Stage and atomically publish the unique session entry and portal integration.
9. Run read-only post-install checks. Never terminate the current desktop or force logout.
10. Commit the transaction only after files and metadata match the manifest; the user selects the new session at next login.

Upgrade installs a new version beside the old one; never modifies the active release in place. Switch the pointer and integration only after validation. Keep the previous release for rollback. Uninstall removes only files whose current hashes still match the manifest; edited/replaced files are preserved and reported. Never remove host RPMs or user-installed Hyprland packages.

On failure, restore only transaction-owned changes and retain a recovery record. Never claim that a native DNF transaction can be rolled back.

## 6. Required acceptance matrix

| Area | Evidence required |
|---|---|
| Reproducibility | Fedora 44/45 image digests, repository metadata identity, RPM NEVRAs/hashes, source manifest |
| Artifact integrity | Full manifest, every ELF dependency resolved, no build-path leakage, private RUNPATH containment |
| Session | GDM sees both original and SekaiPop sessions; original remains launchable |
| Runtime | Login/logout/relaunch, environment, hyprctl, XWayland, D-Bus and user systemd |
| Graphics | Mesa and NVIDIA proprietary driver; DRM/GBM/EGL and hybrid-GPU behavior |
| Quickshell | QML imports, Qt plugins, shaders, clipboard, screenshots, notifications, audio, display changes |
| Portal | ScreenCast, Screenshot, FileChooser, chooser precedence and backend coexistence |
| Lifecycle | Suspend/resume, lock/unlock, reboot, crash, failed launcher, interrupted install |
| Recovery | Upgrade, pointer rollback, partial uninstall, edited-file collision, crash recovery |
| Security | Rootless build, no privileged container, no global loader changes, symlink/path traversal resistance |

All destructive and failure-injection tests run only in disposable VMs with snapshots. Container smoke is not a substitute.

## 7. Implementation phases and stop conditions

**Phase A — provenance and builder:** pin image digests and exact RPM inputs; consolidate source pins; export the built prefix from rootless Podman; extend ELF/manifest validation; test export and cleanup failures.

**Phase B — host transaction primitives:** safe root-owned release publication; hash-based ownership manifest; collision refusal; atomic active pointer; recovery journal; mocked symlink, edited-file, partial-write, interrupted-rename, and rollback tests.

**Phase C — session and portal:** unique GDM session, scoped launcher, verified portal metadata/activation, session-local environment; Fedora 44/45 VM validation before exposing an installer option.

**Phase D — opt-in release candidate:** experimental provider only after Phases A-C and native tests pass. Default package plan remains unchanged until separate review approves the Fedora support claim.

Stop if the display manager cannot discover the isolated session, portal activation cannot coexist safely, any private ELF dependency is unresolved, global loader changes are required, or the previous Hyprland session cannot be preserved.

## 8. Non-goals

No automatic COPR/third-party repository; no replacement of the system Hyprland executable or default session; no global loader changes; no host-side compilation with a large development RPM set; no claim that container success certifies NVIDIA, Mesa, portals, or native desktop behavior; no Fedora Atomic/ostree, derivative, non-x86_64, or unsupported-release support.
