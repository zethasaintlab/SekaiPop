## Status

This checklist is pending execution on actual native or VM installs. No distribution is certified by its presence.

The matrix below is a **test plan**, not a claim that these installations have already passed. Run each baseline in a disposable UEFI x86_64 VM with a systemd desktop, a clean snapshot, a second snapshot after first login, and a recovery snapshot before testing rollback. Keep the VM's package sources at their documented baseline and do not add an unreviewed repository merely to make the package planner green.

| Baseline | Clean install | Existing-provider/service preservation | Restore/failure test | Additional conditions |
|---|---|---|---|---|
| Arch Linux rolling | Pending | Pending | Pending | Test fresh/current sync DB and stale DB separately. Verify stale DB refuses without `--system-upgrade`; with authorization confirm `pacman -Syu --needed` before package resolution. |
| EndeavourOS rolling | Pending | Pending | Pending | Verify exact ID routing to Arch profile and preserve EndeavourOS-specific desktop defaults. |
| CachyOS rolling | Pending | Pending | Pending | Verify exact ID routing to Arch profile and preserve CachyOS kernel/GPU packages. |
| Fedora 44 | Pending | Pending | Pending | Compatible Hyprland >= 0.55 must be user-provided. Test default TuneD PPD and separately test an existing TLP PPD or power-profiles-daemon provider. Do not enable a COPR. |
| Debian 13 trixie | Pending | Pending | Pending | Configure official trixie-backports before the test. Repeat once without backports and confirm the planner fails safely without editing APT sources. |
| Ubuntu 26.10 | Pending | Pending | Pending | Confirm Universe is enabled. Repeat with Universe absent and verify the planner does not edit repository configuration. |
| Kali rolling | Pending | Pending | Pending | Test canonical kali-rolling sources, then mixed-suite, third-party, malformed deb822, insecure trust, and custom APT path rejection. Confirm there is no APT full-upgrade. |

### Test sequence for every VM

1. Record `/etc/os-release`, architecture, kernel, desktop/session manager, package-manager version, Hyprland/Qt/Quickshell versions, and the enabled APT/DNF/pacman repositories. Take a clean VM snapshot.
2. Run `./install.sh --check` and `./install.sh --plan --profile standard --no-log`. Save the complete output. Confirm the plan uses only the documented native backend and repository policy.
3. Run the installer interactively from the normal desktop user (never as root). Read every package and service confirmation; do not use `--yes` for the first clean-install certification.
4. Log out/in to the plain Hyprland session. Verify the generated or merged config with `hyprctl configerrors`, confirm exactly one SekaiPop instance exists for `~/.config/quickshell/sekaipop`, and exercise the bar, dock, notification/polkit flows, wallpaper/shaders, audio, screen capture, portals, suspend/lock and display settings.
5. On Fedora/KDE, confirm Plasma remains available from the display manager and its global portal/default app settings are unchanged. Confirm SekaiPop only touches the named Hyprland config and the selected path-scoped Quickshell instance.
6. Verify the systemd journal: compare `systemctl is-enabled/is-active` and `systemctl --user is-enabled/is-active` before and after install. Confirm units that were already active were not restarted or disabled.
7. Run `./install.sh --restore`. Confirm both the original Quickshell and Hyprland trees return byte-for-byte, the current config is retained in a separate recovery snapshot, and unrelated application state under `~/.local/state/sekaipop` remains intact.
8. Re-run `./install.sh --check` and capture the installer log, state manifest, backup manifests, and service-state comparison. Revert the VM to its clean snapshot before the next distro.

### Rollback fault injection

On a **disposable VM only**, a Quickshell wrapper can make the daemon launch command return success while reporting that the target config path never becomes a running instance. This exercises the timeout → automatic config/service rollback path without killing an unrelated Quickshell process. Run from a clean graphical session with no SekaiPop instance already running:

```bash
real_qs="$(command -v qs)"
fault_dir="$(mktemp -d)"
cat > "$fault_dir/qs" <<'WRAPPER'
#!/usr/bin/env bash
if [[ "$1" == list && "$2" == -p ]]; then
    printf 'No running instances\\n'
    exit 0
fi
if [[ "$1" == -p && "$3" == -n && "$4" == -d ]]; then
    exit 0
fi
exec "${SEKAIPOP_REAL_QS:?}" "$@"
WRAPPER
chmod 0755 "$fault_dir/qs"
SEKAIPOP_REAL_QS="$real_qs" PATH="$fault_dir:$PATH" \\
    QS_STARTUP_ATTEMPTS=10 QS_STARTUP_INTERVAL=0.1 \\
    ./install.sh --profile standard
rm -rf "$fault_dir"
```

Expected result: activation times out; the installer exits nonzero; previous configuration is restored; the service journal is reversed; no successful state manifest is written for the failed transaction. Package installations completed earlier in the run remain installed by design. Re-run `./install.sh --check`, inspect the recovery snapshot, then revert the VM snapshot.

### Evidence and certification record

For every baseline, retain: VM image/version and snapshot ID; installer commit SHA; package plan; package transaction output; host/runtime checks; Hyprland config errors; Qt/QML/shader checks; service-state before/after diff; restore result; injected-failure result; and the redacted installer log. Mark a distro **VM-certified** only after the complete sequence passes on that distro's actual VM image. Container package-resolution success and the Fedora 44 reference-host smoke baseline must remain separate evidence categories.
