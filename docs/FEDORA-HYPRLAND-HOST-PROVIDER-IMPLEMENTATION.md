# Fedora Hyprland host-provider implementation notes

Status: **experimental implementation in draft PR #20; not enabled by the normal installer**

This document records the exact scope of the current host-provider implementation. It must not be interpreted as proof of a complete graphical desktop installation.

## Provider decision

The provider uses the pinned SekaiPop-managed Hyprland v0.57.1 + xdg-desktop-portal-hyprland v1.5.0 source closure. It does not enable COPR or another third-party repository. Build dependencies come from the matching official Fedora 44 or Fedora 45 container image and its enabled official DNF repositories.

The build pipeline uses reviewed Fedora 44/45 base-image digests recovered from successful PR #18 provenance artifacts and committed in `tools/fedora-hyprland-base-images.lock.json`. It validates the enabled repository set, official Fedora metalinks, local Fedora signing-key identity, and `pkg_gpgcheck=true` before the build. Repository configuration and signing-key SHA256 values are recorded. The existing immutable source-fetch script and provenance writer capture source commits, toolchain identity, repository metadata, and the installed RPM NEVRA inventory. Compilation and installation run in a rootless Podman container with networking disabled.

## Current implementation

- `installer/providers/fedora/host-provider.sh`: read-only platform, rootless Podman, staging-filesystem and Podman-store preflight checks.
- `tools/fedora-hyprland-host-build.sh`: builds the Fedora-specific builder image, exports a versioned private-prefix tree into a user-owned staging directory, retains build logs, and generates an ownership manifest.
- `tools/fedora-hyprland-host-manifest.py`: records every directory, regular file and symlink; hashes regular files; rejects special files, hard links, setuid/setgid modes, world-writable artifacts, dangling links and links escaping the final runtime prefix. The manifest can be revalidated before publication.
- `tools/fedora-hyprland-base-images.lock.json`: immutable official Fedora base-image digest lock, tied to the verified PR #18 provenance artifacts.
- `tools/fedora-hyprland-host-prepare-session.sh`: adds a version-scoped session launcher and a unique Wayland session desktop entry to the staged prefix before the manifest is generated.
- `tools/fedora-hyprland-host-user-integration.sh`: creates/removes only the two per-user systemd unit symlinks required by the pinned Hyprland session target and portal backend. Conflicting user units are preserved; failed activation/reload rolls back newly created links.
- `tools/fedora-hyprland-host-deploy.py`: privileged publication, display-manager session registration and removal helper. It validates the invoking user and staging location, checks the pinned source/build provenance and complete artifact manifest, copies into a same-filesystem temporary directory beneath `/opt/sekaipop/providers/hyprland/releases`, revalidates the copied tree, and uses atomic no-replace publication. It registers only a unique `/usr/share/wayland-sessions/sekaipop-hyprland.desktop` entry, refuses conflicting entries, and removes it only when its exact content and ownership still match. Release removal is refused until the session entry is unregistered and the installed tree still matches its ownership manifest.
- Regression fixtures cover platform/preflight gates, manifest tampering and path containment, and atomic no-replace publication.

The build and publication phases are separate. The builder does not use sudo and does not write to host system directories. The publication helper is the only component that writes under `/opt/sekaipop`, and it refuses existing or modified release paths.

## Development-only invocation

From a complete checkout on a Fedora 44/45 x86_64 mutable systemd host with rootless Podman already available:

```bash
bash tools/fedora-hyprland-host-build.sh
```

The script prints a staging path similar to:

```text
/var/tmp/sekaipop-fedora-provider-<uid>/build.<random>/0.57.1-acc1aa0bfd4b-portal-1.5.0-d1467fea8d18
```

After inspecting the generated manifest and provenance, the separate publication helper can publish that exact staged release:

```bash
sudo python3 tools/fedora-hyprland-host-deploy.py publish \
  --stage /var/tmp/sekaipop-fedora-provider-<uid>/build.<random>/0.57.1-acc1aa0bfd4b-portal-1.5.0-d1467fea8d18
```

```bash
sudo python3 tools/fedora-hyprland-host-deploy.py register-session
bash tools/fedora-hyprland-host-user-integration.sh install \
  /opt/sekaipop/providers/hyprland/releases/0.57.1-acc1aa0bfd4b-portal-1.5.0-d1467fea8d18
```

Removal must happen in reverse order so the display manager never points at a deleted release:

```bash
bash tools/fedora-hyprland-host-user-integration.sh remove \
  /opt/sekaipop/providers/hyprland/releases/0.57.1-acc1aa0bfd4b-portal-1.5.0-d1467fea8d18
sudo python3 tools/fedora-hyprland-host-deploy.py unregister-session
sudo python3 tools/fedora-hyprland-host-deploy.py remove
```

Replace the displayed staging path with the exact path printed by the build command. These are engineering diagnostics, not the intended end-user installation workflow.

## Installer transaction journal foundation

The installer now creates a user-owned journal under `$XDG_STATE_HOME/sekaipop/installer-transactions` (default: `~/.local/state/sekaipop/installer-transactions`) for real, non-dry-run installations.

- The journal uses a versioned, append-only TSV record format; event details and metadata are base64-encoded rather than evaluated as shell.
- Each append is serialized with `flock`, followed by `sync -f`; journals and lock files are private, user-owned, singly-linked regular files.
- The transaction records the owning installer PID, its Linux process start time, and the boot ID to distinguish a live transaction from a stale PID reused by another process.
- Unexpected shell exit records `needs_recovery`. Before a new install, stale active transactions are marked `needs_recovery` and the installer fails closed rather than deleting or guessing at partial state.
- The main installer records native dependency planning, Quickshell deployment, Hyprland configuration integration, runtime validation, systemd integration, activation, and rollback events. Successful deployment and dependency-only flows record a commit.
- This is a durable journal and interruption gate, not yet a provider state machine or automatic cross-component recovery engine. The Fedora provider is still not invoked by `install.sh`; a recovery-required transaction currently requires inspection before retry.

Package-manager operations are not claimed to be reversible. A package transaction that partially applies before failure must be reported accurately; the journal records the attempted/completed phase, while later provider integration must add package ownership and recovery semantics without uninstalling pre-existing packages.

## Explicit limitations

The current implementation does **not** yet:

- Provision Podman automatically through DNF5.
- Invoke the host builder from `./install.sh`.
- Add provider selection to the dependency planner or initial authorization.
- Orchestrate the generated GDM/SDDM session entry and per-user systemd links from `./install.sh`.
- Provision and verify D-Bus activation, portal descriptors and the complete desktop dependency closure automatically.
- Integrate the Quickshell/QML dependency closure and verify its startup from the generated Hyprland session.
- Implement activation, upgrade switching, or end-to-end transaction recovery.
- Freeze the complete RPM payload checksums in a committed package lock (current provenance records NEVRAs, repository metadata, signature policy and signing-key hashes).
- Provision rootless Podman automatically through the Fedora official DNF5 provider.
- Prove Mesa/NVIDIA, display-manager login, portal functionality, suspend/resume or native graphical compatibility.

The published compositor prefix now has a generated launcher, a unique display-manager session entry, and scoped user-systemd integration helpers. These are still development-only building blocks: they are not yet orchestrated by `./install.sh`, Quickshell/QML provisioning is not complete, and the runtime stack has not been validated in a native graphical Fedora session. The normal Fedora installer behavior remains unchanged and still requires an already-installed compatible Hyprland.

Do not promote the provider to the default installation path until the missing integration, automated dependency provisioning, failure-injection tests, and Fedora 44/45 native VM acceptance gates are complete.
