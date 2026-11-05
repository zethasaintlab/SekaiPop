# Native and VM acceptance protocol

This document defines the manual acceptance boundary for SekaiPop's universal installer. Automated fixtures and container package-plan jobs do not certify a native installation, graphical session, shader runtime, suspend/resume behavior, or restore cycle.

**Run installation and destructive recovery tests only in disposable VMs or on a machine with a verified full-system snapshot.** Do not use the failure-injection scenarios on a daily-driver host. The installer does not roll back native package transactions after a later deployment failure; it preserves configuration snapshots and service rollback state where possible.

## 1. Supported test matrix

| Target | Required baseline | Preconditions |
|---|---|---|
| Fedora 44 | x86_64, mutable, systemd | Existing trusted Hyprland >= 0.55 |
| Fedora 45 | x86_64, mutable, systemd | Existing trusted Hyprland >= 0.55 |
| Arch Linux | x86_64, rolling, systemd | Normal synchronized repositories; stale DB requires explicit full-upgrade authorization |
| Debian 13 | x86_64, trixie, systemd | Official trixie-backports (main) already configured with the system Debian archive keyring |
| Ubuntu 26.10 | x86_64, systemd | Official Universe already enabled for release, updates, and security |
| EndeavourOS / CachyOS | x86_64, systemd | Arch-compatible package profile; additional native validation required |

Kali, openSUSE, Fedora Atomic/ostree, unsupported derivatives, and non-x86_64 architectures must be rejected. Fedora derivatives are not implicitly supported.

For every baseline, test both a clean VM and an existing-user configuration where practical. On Fedora, include a minimal installation as well as a normal workstation installation. Keep a VM snapshot before each installation and before restore/failure tests.

## 2. Capture the baseline

From the complete repository checkout:

```bash
git status --short
git rev-parse HEAD
cat /etc/os-release
uname -m
systemctl --version
./install.sh --version
```

Expected:
- Working tree is clean; record the exact installer commit SHA and use that same reviewed revision for every test result.
- Distribution ID, release, codename, and architecture match one explicitly supported profile.
- Architecture is `x86_64`.
- systemd is the active init system.
- Installer version reports `2.1.0`.

Capture the installed desktop/runtime state:

```bash
command -v Hyprland hyprctl qs qsb qtpaths6 || true
Hyprland --version 2>&1 || true
qs --version 2>&1 || true
qtpaths6 --query QT_VERSION 2>&1 || true

```

On Fedora, also record configured repositories and relevant packages:

```bash
dnf5 repolist --enabled
rpm -q dnf5 qt6-qtbase qt6-qtdeclarative qt6-qtmultimedia quickshell tuned-ppd power-profiles-daemon 2>&1 || true
```

On Arch:

```bash
pacman -Q pacman qt6-base qt6-declarative quickshell hyprland 2>&1 || true
pacman -Si quickshell hyprland qt6-base qt6-declarative 2>&1 || true
```

On Debian 13:

```bash
grep -RhsE '^(deb |URIs:|Suites:|Components:)' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
apt-cache policy quickshell hyprland qt6-base-dev qt6-declarative-dev
```

Record whether official trixie-backports is already configured. If it is missing, stop the test and configure it manually before running SekaiPop. Example Deb822 entry (create it yourself as `/etc/apt/sources.list.d/debian-backports.sources`):\n\n```text\nTypes: deb\nURIs: https://deb.debian.org/debian\nSuites: trixie-backports\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\n```\n\nThen run `sudo apt update`. Verify the source is enabled and official before continuing. SekaiPop must not create or modify this file.

On Ubuntu 26.10:

```bash
grep -RhsE '^(deb |URIs:|Suites:|Components:)' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
apt-cache policy quickshell hyprland qt6-base-dev qt6-declarative-dev
```

Record whether official Universe is already enabled for the release, updates, and security suites. If it is missing or incomplete, stop the test, enable Universe using Ubuntu's supported repository-management tool (for example, `sudo add-apt-repository universe` where available), then run `sudo apt update`. Reinspect the active source configuration and verify that all three suites expose Universe through official Ubuntu archive URIs. SekaiPop must not create or modify source files.

## 3. Read-only detection and package planning

Run:

```bash
./install.sh --plan --profile minimal
./install.sh --plan --profile standard
./install.sh --plan --profile full
./install.sh --check
```

Expected:
- Exact distribution/release detection; no `ID_LIKE` fallback.
- Unsupported releases and excluded distributions fail closed.
- Read-only `--plan` and `--check` do not add repositories. They report missing required official APT sources. Actual installation fails closed until Debian backports or Ubuntu Universe is configured manually.
- No COPR, PPA, AUR helper, third-party repository, unverified package source, or unpinned source build is enabled.
- Existing trusted Hyprland >= 0.55 satisfies the compositor requirement; a missing or incompatible compositor is reported rather than silently replaced.
- Qt 6.7 or newer is required.
- If effective Qt is below 6.12, Qt Shader Tools is required for rebuilding shipped shader bytecode. If the effective version cannot be established, the dependency must remain explicitly unresolved.
- Missing optional packages are reported as optional; they must not be misreported as installed.
- The plan/check commands do not write configuration, create backups, change services, or perform package transactions.

For Arch with a missing or stale sync database, a read-only plan may warn that package candidates are incomplete. A real installation must refuse an unsafe partial `pacman -Sy`; only the explicit `--system-upgrade` path may authorize a full `pacman -Syu` transaction.

## 4. Installation scenarios

Run the following only after reviewing the plan and confirming the VM snapshot:

```bash
./install.sh --profile standard
./install.sh --check
```

Repeat in separate snapshots with:

- Clean Fedora 44 and Fedora 45.
- Fedora minimal installation with a trusted compatible Hyprland already installed.
- Existing user environment containing custom Quickshell settings, presets, user data, and Hyprland configuration.
- Required dependencies already installed.
- One or more required dependencies missing.
- Optional dependencies missing or unavailable.
- `--profile minimal`, `standard`, and `full`.
- `--no-deps` only when all required runtime dependencies are already present.
- `--no-update` with valid existing package metadata.

Expected:
- Native package manager resolves the declared package candidates.
- APT/DNF metadata is refreshed before candidate resolution when requested. SekaiPop never edits APT sources; Debian backports and Ubuntu Universe must already be configured. If metadata refresh fails, the installer stops without changing APT source configuration.
- Existing user settings and custom data are preserved.
- The persistent `~/.local/state/sekaipop` directory is not replaced as part of Quickshell deployment.
- Package transactions are not falsely described as rolled back if deployment later fails.
- A second installation is safe and does not create duplicate autostart hooks or corrupt existing customizations.

Do not use `--yes` for the first acceptance run. Verify each confirmation before accepting it.

## 5. Deployment and service checks

Test each supported Hyprland mode in a disposable VM:

```bash
./install.sh --profile standard --hypr merge
./install.sh --check
```

For `merge`, verify the installer adds only the intended SekaiPop integration and does not overwrite unrelated user settings. Test `--hypr full` only on a disposable VM because it deploys the complete SekaiPop Hyprland configuration. Test `--hypr skip` to confirm Hyprland files are untouched.

Check Quickshell deployment and activation:

```bash
qs list
qs -p "$HOME/.config/quickshell/sekaipop" -n -d
qs list
```

Expected:
- The SekaiPop path appears as a running instance after successful activation.
- Restart and rollback operations are scoped to the SekaiPop config path.
- Unrelated Quickshell instances remain running.
- Activation failure is surfaced as installation failure; it is not silently accepted as success.
- With no active Hyprland session, activation is explicitly deferred to the next login.

Inspect service state before and after installation:

```bash
systemctl is-enabled NetworkManager.service bluetooth.service upower.service 2>&1 || true
systemctl is-active NetworkManager.service bluetooth.service upower.service 2>&1 || true
systemctl --user is-enabled pipewire.service pipewire-pulse.service wireplumber.service 2>&1 || true
systemctl --user is-active pipewire.service pipewire-pulse.service wireplumber.service 2>&1 || true
```

Expected:
- Active services are left untouched.
- Masked services are not unmasked.
- Only existing inactive services are offered for activation.
- Disabled units are enabled and started as separate operations.
- Previously enabled but inactive units are started without being re-enabled.
- If a service action fails, the installer attempts to restore its original enabled/disabled and active/inactive state.
- Fedora must not activate competing TuneD PPD, TLP PPD, or power-profiles-daemon providers. Ambiguous or conflicting provider states must be left untouched and reported.

## 6. Graphical and runtime acceptance

After logging into the installed Hyprland session:

```bash
hyprctl configerrors
qs -c sekaipop log
./check-deps.sh
```

Expected:
- Hyprland reports no new configuration errors.
- SekaiPop loads without missing QML modules, plugins, or Quickshell modules.
- Launcher opens and accepts normal text queries.
- AppSource search, desktop-entry rescans, and ranking return consistent results.
- Lyrics Widget provider selection and timing controls remain interactive.
- Lockscreen and calendar render; lock/unlock does not leave the shell in a stale state.
- Region selector, quick panel, Settings, and touchpad configuration work.
- Keyboard layout, network, Bluetooth, audio, and media integrations behave according to the host's available services.

For shader behavior:

```bash
command -v qsb || true
find "$HOME/.config/quickshell/sekaipop/shaders" -maxdepth 1 -type f -name '*.qsb' -printf '%f\n' | sort
```

If Qt is older than 6.12, verify the staged shader compilation completed successfully and the generated `.qsb` files were deployed. Test wallpaper transitions and lockscreen transitions visually; the presence of `qsb` alone is not proof that shaders work.

Suspend and resume the VM/host. Verify:
- Graphical session returns without a black screen.
- Quickshell remains responsive.
- Lock screen clock/calendar refresh.
- Audio, network, Bluetooth, and touchpad integrations recover.
- No duplicate Quickshell instance appears.

## 7. Backup and restore cycle

Before restore, record hashes and metadata for the configuration trees:

```bash
find "$HOME/.config/quickshell/sekaipop" -type f -print0 | sort -z | xargs -0 sha256sum
find "$HOME/.config/hypr" -type f -print0 | sort -z | xargs -0 sha256sum
```

Run:

```bash
./install.sh --restore
```

Expected:
- The user is shown the selected snapshot and must confirm.
- Current Quickshell and Hyprland trees are preserved in a separate recovery snapshot before any restore modification.
- If the recovery snapshot cannot be completed, restore aborts without modifying either destination.
- The selected snapshot is validated before use.
- Restored trees match the selected snapshot, including permissions and symlink targets.
- Systemd services return to their pre-install state when rollback is part of a failed deployment.
- Recovery snapshots remain available after restoration.

Repeat with:
- Existing Quickshell config only.
- Existing Hyprland config only.
- Both trees present.
- One or both destinations absent before installation.
- Existing custom settings and symlinks.
- An intentionally malformed snapshot in a disposable test fixture; it must be rejected without changing user data.

## 8. Failure and interruption recovery

Use a cloned VM snapshot for each injected failure. Do not deliberately interrupt package transactions on a daily-driver machine.

Required fixture/native scenarios:
- Package manager returns a non-zero status.
- Source build or shader compilation fails.
- Staged Quickshell deployment fails before replacement.
- Hyprland integration fails after Quickshell deployment.
- Quickshell activation command fails or the path never becomes active.
- Systemd enable succeeds but start fails.
- Systemd rollback fails.
- State manifest write/rename fails.
- Recovery snapshot copy fails.
- Restore fails after one configuration tree has been replaced.
- Installer receives SIGINT or SIGTERM during a staged deployment.
- Repeated installer invocation while another instance holds the lock.

Expected:
- No package repository or unrelated system configuration is silently changed.
- Existing configuration is preserved whenever a complete snapshot could be created.
- A failed deployment returns a non-zero status and retains a recovery snapshot.
- Failed service recovery is explicitly reported; do not assume that an error message means rollback succeeded.
- An interrupted operation must be inspected manually before retrying. Do not claim power-loss atomicity: package transactions, filesystem replacement across two separate config trees, and service activation are not one indivisible OS transaction.

## 9. Diagnostics and failure report

Capture these outputs after any failure:

```bash
date --iso-8601=seconds
cat /etc/os-release
uname -a
./install.sh --version
./install.sh --plan --profile standard
./install.sh --check
find "$HOME/.local/state/sekaipop/installer-backups" -maxdepth 3 -type f -printf '%p\n' 2>/dev/null
find "$HOME/.cache/sekaipop/installer" -maxdepth 1 -type f -printf '%p\n' 2>/dev/null
systemctl --failed --no-pager
systemctl --user --failed --no-pager 2>&1 || true
journalctl -b -p warning..alert --no-pager
journalctl --user -b -p warning..alert --no-pager 2>&1 || true
hyprctl configerrors 2>&1 || true
qs -c sekaipop log 2>&1 || true
```

Attach the exact failing command, exit status, complete installer log, package-manager error output, and whether configuration/service rollback completed. Redact usernames, hostnames, tokens, private paths, and personal configuration contents before sharing logs. Do not upload full `~/.config` or `~/.local/state` trees.

## 10. Certification record

For every tested baseline, record:

- Distribution, release, codename, architecture, VM image/snapshot ID.
- Installer commit SHA.
- Package-manager, Qt, Quickshell, Hyprland, and qsb versions.
- Repository configuration before and after the test.
- Plan output and actual package transaction result.
- Whether the host was clean, minimal, or an existing user environment.
- Quickshell and Hyprland deployment mode.
- Service state before and after.
- Runtime feature results and suspend/resume outcome.
- Restore result and recovery snapshot location.
- Exact failing command, exit status, and diagnostic log for failures.

A distribution baseline is certified only after clean installation, runtime/graphical validation, and restore-cycle acceptance have all passed on that baseline. CI package-plan success alone does not certify a distribution.

 
## 11. Fedora pinned Hyprland source-build smoke (container only)

The CI source-build job is a **container build and install-prefix smoke test**, not a native host provider and not a host installation. It acquires immutable upstream source pins and Fedora build dependencies during the image build, then builds and installs with container networking disabled. It does not modify the host package database, systemd directories, desktop-session registry, or boot configuration.

Run from a clean repository checkout with Docker or a compatible Docker CLI:

```bash
set -Eeuo pipefail
SMOKE_DIR="$PWD/.sekaipop-hyprland-smoke"
mkdir -p "$SMOKE_DIR/44" "$SMOKE_DIR/45"

for release in 44 45; do
  docker build --progress=plain \
    --build-arg FEDORA_VERSION="$release" \
    --file tools/fedora-hyprland-build-smoke.Dockerfile \
    --tag "sekaipop-fedora-hyprland:$release" .

  docker run --rm --network none \
    --volume "$SMOKE_DIR/$release:/artifacts" \
    --env SEKAIPOP_HYPR_PREFIX="/artifacts/prefix" \
    "sekaipop-fedora-hyprland:$release"
done
```

The image build needs network access to retrieve pinned upstream source and official Fedora build dependencies. The runtime build phase runs with `--network none`. Output is isolated beneath `.sekaipop-hyprland-smoke/`. Remove it after inspection:

```bash
rm -rf -- .sekaipop-hyprland-smoke
```

The smoke must end with `FEDORA_HYPRLAND_SOURCE_BUILD_SMOKE_OK`. It verifies pinned pkg-config versions, executable artifacts, ELF dependency resolution, private-prefix RPATH/RUNPATH, session desktop entry, portal descriptor, D-Bus service, portal user service, and the Hyprland systemd user target:

- `prefix/bin/Hyprland`
- `prefix/bin/start-hyprland`
- `prefix/bin/hyprctl`
- `prefix/bin/hyprwire-scanner`
- `prefix/libexec/xdg-desktop-portal-hyprland`
- `prefix/lib64/systemd/user/hyprland-session.target`
- `prefix/share/wayland-sessions/hyprland.desktop`
- `prefix/share/xdg-desktop-portal/portals/hyprland.portal`
- `prefix/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service`
- `prefix/lib/systemd/user/xdg-desktop-portal-hyprland.service`

Every CMake install manifest is validated artifact-by-artifact. Both lexical and symlink-resolved paths must remain inside the private prefix. Missing files, path traversal, and symlinks escaping the prefix fail the smoke. The Hyprland manifest must explicitly contain the required systemd session target. An artifact installed into `/usr`, `/lib64`, or another system path is a failure, even if the build succeeds.

A failed Docker build, non-zero container exit, missing success marker, missing required artifact, unresolved ELF dependency, or prefix escape is a failed smoke test. Preserve the full build log when reporting a failure.

**Important scope boundary:** this smoke does not integrate the compiled compositor into the SekaiPop installer lifecycle. The current Fedora installer still requires a compatible trusted Hyprland installation already present on the target host. It does not install this container-built prefix onto the host, register its session target, configure runtime library paths, or switch the display-manager session. Native installation must continue to follow the existing-Hyprland precondition in Sections 1 and 3. Do not interpret the container smoke as proof of a complete automatic Fedora compositor installation.
