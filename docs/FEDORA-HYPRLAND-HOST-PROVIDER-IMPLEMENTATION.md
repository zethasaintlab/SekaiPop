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
- `tools/fedora-hyprland-host-deploy.py`: privileged publication/removal helper. It validates the invoking user and staging location, checks the pinned source/build provenance and complete artifact manifest, copies into a same-filesystem temporary directory beneath `/opt/sekaipop/providers/hyprland/releases`, revalidates the copied tree, and uses an atomic no-replace directory rename. Removal is permitted only when the installed tree still matches its ownership manifest.
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

The helper's `remove` action removes only the exact pinned release after verifying its complete manifest and provenance:

```bash
sudo python3 tools/fedora-hyprland-host-deploy.py remove
```

Replace the displayed staging path with the exact path printed by the build command. These are engineering diagnostics, not the intended end-user installation workflow.

## Explicit limitations

The current implementation does **not** yet:

- Provision Podman automatically through DNF5.
- Invoke the host builder from `./install.sh`.
- Add provider selection to the dependency planner or initial authorization.
- Register a unique GDM/SDDM session.
- Install or reconcile user systemd units, the Hyprland session target, D-Bus activation metadata or portal descriptors.
- Configure session-local `PATH` and `XDG_DATA_DIRS`.
- Integrate the Quickshell/QML dependency closure.
- Implement activation, upgrade switching, or end-to-end transaction recovery.
- Prove Mesa/NVIDIA, display-manager login, portal functionality, suspend/resume or native graphical compatibility.

The published compositor prefix is therefore an immutable artifact only; it is not yet a ready-to-login desktop session. The normal Fedora installer behavior remains unchanged and still requires an already-installed compatible Hyprland.

Do not promote the provider to the default installation path until the missing integration, automated dependency provisioning, failure-injection tests, and Fedora 44/45 native VM acceptance gates are complete.
