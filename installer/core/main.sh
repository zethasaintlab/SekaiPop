#!/usr/bin/env bash
source "$SEKAIPOP_INSTALLER_ROOT/installer/core/common.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/core/detect.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/core/cli.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/provisioning/apt-repositories.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/providers/fedora/host-provider.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/catalog/requirements.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/package-managers/interface.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/core/plan.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/core/backup.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/integrations/quickshell.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/integrations/shaders.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/integrations/systemd.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/integrations/hyprland.sh"
source "$SEKAIPOP_INSTALLER_ROOT/installer/core/deployment.sh"

sp_pacman_sync_db_fresh() {
    local newest=0 file mtime now
    shopt -s nullglob
    local -a databases=(/var/lib/pacman/sync/*.db)
    shopt -u nullglob
    (("${#databases[@]}")) || return 1
    now="$(date +%s)"
    for file in "${databases[@]}"; do
        mtime="$(stat -c %Y "$file" 2>/dev/null || echo 0)"
        (( mtime > newest )) && newest="$mtime"
    done
    (( newest > 0 && now - newest < 604800 ))
}
sp_runtime_hyprland_check() {
    local version
    version="$(sp_hyprland_version || true)"
    [[ -n "$version" ]] || { sp_error 'Hyprland executable/version could not be detected.'; return 1; }
    sp_version_ge "$version" 0.55.0 || { sp_error "Hyprland $version is below SekaiPop's 0.55.0 Lua baseline."; return 1; }
    sp_ok "Hyprland $version (minimum 0.55.0)"
}
sp_runtime_qt_qml_check() {
    local root module failures=0
    root="$(sp_qml_import_root || true)"
    [[ -n "$root" ]] || { sp_error 'Qt QML import root not detected.'; return 1; }
    local -a modules=(QtMultimedia QtQuick/Effects QtQuick/Shapes Qt/labs/folderlistmodel)
    for module in "${modules[@]}"; do
        if [[ -f "$root/$module/qmldir" ]]; then sp_ok "Qt QML module $module"
        else sp_error "Missing Qt QML module $module (expected $root/$module/qmldir)"; failures=$((failures + 1)); fi
    done
    (( failures == 0 ))
}
sp_runtime_basic_check() {
    local failures=0 bin
    local -a required=(systemctl jq curl git xdg-open nmcli bluetoothctl upower notify-send wpctl pactl wl-copy wl-paste fc-list)
    local -a optional=(xdg-user-dir python3 brightnessctl ddcutil grim slurp swappy wf-recorder playerctl cava matugen)
    for bin in "${required[@]}"; do
        if sp_have "$bin"; then sp_ok "Executable $bin"; else sp_error "Missing required executable $bin"; failures=$((failures + 1)); fi
    done
    if (( ! SP_CHECK_CORE )); then
        for bin in "${optional[@]}"; do sp_have "$bin" && sp_ok "Optional executable $bin" || sp_warn "Optional executable $bin is unavailable."; done
    fi
    if (( ! SP_CHECK_CORE )) && sp_have matugen; then
        local matugen_version
        matugen_version="$(matugen --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true)"
        if [[ -n "$matugen_version" ]] && sp_version_ge "$matugen_version" 2.0.0; then sp_ok "matugen $matugen_version"
        else sp_warn "matugen version ${matugen_version:-unknown}; SekaiPop expects matugen 2.x or newer."; fi
    fi
    if (( ! SP_CHECK_CORE )) && sp_have fc-match; then
        fc-match -f '%{family}\n' 'Material Symbols Rounded' 2>/dev/null | grep -qi 'Material Symbols' && sp_ok 'Material Symbols Rounded font' || sp_warn 'Material Symbols Rounded font is missing; some icons may use a fallback glyph.'
        fc-match -f '%{family}\n' 'Google Sans Flex' 2>/dev/null | grep -qi 'Google Sans Flex' && sp_ok 'Google Sans Flex font' || sp_warn 'Google Sans Flex font is missing; typography will use the fontconfig fallback.'
    fi
    if (( ! SP_CHECK_CORE )); then
        if sp_have python3 && python3 -c 'import numpy' >/dev/null 2>&1; then sp_ok 'Python NumPy module'
        else sp_warn 'Python NumPy is unavailable; the audio analyzer will use its fallback where supported.'; fi
    fi
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" || -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]]; then sp_ok 'User D-Bus session bus'
    else sp_warn 'No user D-Bus session bus in this process; run SekaiPop from a real desktop login.'; fi
    if sp_have pkaction || [[ -x /usr/lib/polkit-1/polkitd || -x /usr/libexec/polkit-1/polkitd ]]; then sp_ok 'PolicyKit runtime'
    else sp_error 'PolicyKit daemon/runtime was not found.'; failures=$((failures + 1)); fi
    (( failures == 0 ))
}
sp_check_all() {
    local failed=0
    printf 'SekaiPop dependency/runtime check\n'
    printf 'System: %s | %s %s | %s | %s\n\n' "$SP_DISTRO_NAME" "$SP_DISTRO_ID" "$SP_DISTRO_VERSION" "$SP_ARCH" "$SP_BACKEND"
    sp_runtime_hyprland_check || failed=1
    sp_verify_qt_runtime || failed=1
    sp_runtime_qt_qml_check || failed=1
    sp_verify_qt_plugins "$SP_CHECK_CORE" || failed=1
    sp_verify_quickshell || failed=1
    sp_runtime_basic_check || failed=1
    if (( failed )); then sp_error 'One or more required SekaiPop runtime checks failed.'; return 1; fi
    sp_ok 'All mandatory SekaiPop runtime checks passed.'
}
sp_validate_preflight() {
    sp_require_normal_user
    [[ "$SP_INIT" == systemd ]] || sp_die 'A systemd-based desktop environment is required. No service changes were attempted.'
    (( SP_NO_DEPS )) || sp_have sudo || sp_die 'sudo is required for native package installation.'
    if sp_have Hyprland || sp_have hyprctl; then
        local version
        version="$(sp_hyprland_version || true)"
        [[ -n "$version" && "$version" != unknown ]] || sp_die 'An existing Hyprland executable was found, but its version could not be verified. Refusing to modify the desktop configuration.'
        sp_version_ge "$version" 0.55.0 || sp_die "Installed Hyprland $version is incompatible with SekaiPop (requires >= 0.55.0). No automatic compositor replacement/downgrade is permitted."
    fi
    local qt_version
    qt_version="$(sp_qt_version || true)"
    if [[ -n "$qt_version" ]] && ! sp_version_ge "$qt_version" 6.7.0; then sp_die "Installed Qt $qt_version is below SekaiPop's 6.7.0 minimum. Upgrade Qt through the distribution's normal package management before installing SekaiPop."; fi
}
sp_plan_and_install_dependencies() {
    sp_load_package_manager
    if (( SP_DRY_RUN )); then sp_apt_report_required_sources; else sp_apt_validate_required_sources; fi
    if (( SP_DRY_RUN )); then
        sp_load_distro_profile
        if [[ "$SP_BACKEND" == arch ]] && ! sp_pacman_sync_db_fresh; then
            if (( SP_SYSTEM_UPGRADE )); then
                sp_warn 'The Arch sync database is missing or stale. This read-only plan cannot run the required pacman -Syu synchronization; candidate resolution may be incomplete.'
            else
                sp_warn 'The Arch sync database is missing or stale. A real install requires explicit --system-upgrade authorization before safe package resolution.'
            fi
        fi
        sp_build_package_plan
        sp_print_package_plan
        (( ${#SP_MISSING_CORE[@]} == 0 )) || { sp_error 'Plan contains unsatisfied mandatory requirements; no installation would be attempted.'; return 1; }
        sp_info 'Plan only: no repository refresh, package transaction, log, backup, directory, or service change was performed.'
        return 0
    fi
    if [[ "$SP_BACKEND" == dnf5 || "$SP_BACKEND" == apt ]]; then
        if (( ! SP_NO_UPDATE )); then
            sp_confirm "Refresh configured native repository metadata for $SP_DISTRO_NAME?" || {
                sp_die 'Metadata refresh declined. Use --no-update only when all required official sources are already configured.'
            }
            if ! pm_refresh_metadata; then
                sp_die 'Native repository metadata refresh failed. No APT source configuration was changed by SekaiPop.'
            fi
        else
            sp_info 'Repository metadata refresh skipped (--no-update).'
        fi
    elif [[ "$SP_BACKEND" == arch ]]; then
        if ! sp_pacman_sync_db_fresh; then
            if (( SP_SYSTEM_UPGRADE )); then
                sp_warn 'Arch sync databases are missing or older than 7 days. A full system synchronization and upgrade is required before dependency resolution.'
                sp_confirm 'Run pacman -Syu --needed now? This will upgrade the entire Arch system.' ||
                    sp_die 'Arch synchronization cancelled. No package database refresh or package transaction was attempted.'
                if pm_refresh_metadata; then
                    :
                else
                    local refresh_status=$?
                    sp_error "Arch full-system synchronization failed (exit $refresh_status); dependency planning was aborted."
                    return "$refresh_status"
                fi
            else
                sp_die 'Arch sync databases are missing or older than 7 days. Refusing an unsafe partial synchronization; rerun with --system-upgrade to authorize pacman -Syu --needed.'
            fi
        fi
    fi
    sp_load_distro_profile
    sp_build_package_plan
    sp_print_package_plan
    if (("${#SP_MISSING_CORE[@]}")); then
        sp_error 'Native configured repositories do not provide every mandatory requirement.'
        if [[ "$SP_DISTRO_ID" == fedora ]]; then sp_error 'The verified Fedora official package profile does not provide the required Hyprland >= 0.55 baseline. Install a compatible compositor from a source you independently trust, then rerun; this installer will not enable a COPR. The Hyprland portal remains an optional desktop feature unless a trusted provider is already configured.'
        elif [[ "$SP_DISTRO_ID" == debian ]]; then sp_error 'Verify that administrator-configured official Debian 13 trixie-backports is enabled and that Quickshell/Hyprland candidates are visible in APT metadata.'; fi
        return 1
    fi
    (("${#SP_MISSING_OPTIONAL[@]}")) || sp_warn 'Some optional feature packages are unavailable. Core installation can continue; those features will be listed in the final report.'
    (("${#SP_INSTALL_PKGS[@]} == 0")) && { sp_ok 'All selected package requirements are already satisfied.'; return 0; }
    sp_confirm "Install ${#SP_INSTALL_PKGS[@]} native package(s) on $SP_DISTRO_NAME?" || sp_die 'Package installation cancelled.'
    if pm_install "${SP_INSTALL_PKGS[@]}"; then
        :
    else
        local install_status=$?
        sp_error "Native package transaction failed (exit $install_status); dependency provisioning was not completed."
        return "$install_status"
    fi

    # A successful package-manager exit is necessary but not sufficient. Re-query
    # the installed state so a no-op/partial backend result cannot pass the gate.
    sp_build_package_plan
    if (( ${#SP_MISSING_CORE[@]} || ${#SP_INSTALL_CORE[@]} )); then
        sp_error 'Native package transaction returned success, but mandatory requirements remain unsatisfied after revalidation.'
        (( ${#SP_MISSING_CORE[@]} )) && printf '  Unavailable: %s\n' "${SP_MISSING_CORE[@]}" >&2
        (( ${#SP_INSTALL_CORE[@]} )) && printf '  Not installed: %s\n' "${SP_INSTALL_CORE[@]}" >&2
        return 1
    fi
    sp_ok 'Native package transaction completed; mandatory requirements were revalidated.'
}
sp_rollback_failed_dependency_only() {
    local reason="$1" service_rollback_failed=0
    if [[ -n "${SP_BACKUP_DIR:-}" ]]; then
        sp_rollback_failed_deployment "$reason"
    fi
    sp_service_transaction_rollback || service_rollback_failed=1
    if (( service_rollback_failed )); then
        sp_die "$reason No desktop configuration was modified, but one or more system/user service states could not be reverted. Inspect the affected units manually."
    fi
    sp_die "$reason No Quickshell/Hyprland configuration was modified; service changes were reverted."
}

sp_rollback_failed_deployment() {
    local reason="$1" original_yes="${SP_YES:-0}" restart_failed=0 service_rollback_failed=0
    sp_error "$reason"
    if (( ${SP_QS_INSTANCE_STARTED_BY_INSTALL:-0} )) && sp_have qs; then
        qs kill -p "$SP_QS_DEST" >/dev/null 2>&1 || true
        sp_wait_qs_instance_state stopped || sp_warn 'Could not confirm shutdown of the newly launched SekaiPop instance during rollback.'
    fi
    sp_service_transaction_rollback || service_rollback_failed=1
    SP_YES=1
    if [[ -n "${SP_BACKUP_DIR:-}" ]] && sp_restore_latest "$SP_BACKUP_DIR"; then
        if (( ${SP_QS_PREVIOUS_INSTANCE_WAS_RUNNING:-0} )); then
            if ! qs -p "$SP_QS_DEST" -n -d >/dev/null 2>&1 || ! sp_wait_qs_instance_state running; then
                restart_failed=1
                sp_warn 'Configuration rollback succeeded, but the previously running SekaiPop instance could not be restarted automatically.'
            else
                sp_ok 'The previously running SekaiPop instance was restarted from the restored configuration.'
            fi
        fi
        SP_QS_INSTANCE_STARTED_BY_INSTALL=0
        SP_QS_PREVIOUS_INSTANCE_WAS_RUNNING=0
        SP_YES="$original_yes"
        if (( restart_failed )); then
            sp_die "$reason Configuration was restored, but the previous Quickshell instance needs to be started manually. Recovery snapshot: $SP_BACKUP_ROOT."
        fi
        if (( service_rollback_failed )); then
            sp_die "$reason Configuration was restored, but one or more system/user service states could not be reverted. Inspect the installer log and run systemctl status on the affected units."
        fi
        sp_die "$reason The previous Quickshell/Hyprland configuration was restored automatically; the recovery snapshot is retained under $SP_BACKUP_ROOT."
    fi
    SP_YES="$original_yes"
    if (( service_rollback_failed )); then
        sp_die "$reason Automatic configuration rollback failed and one or more service states could not be reverted. Keep the installer backup and inspect systemd unit states before retrying."
    fi
    sp_die "$reason Automatic rollback failed. The installer backup remains available; run ./install.sh --restore after inspecting the log."
}

sp_deploy_application() {
    sp_find_rice_source
    sp_create_backup 1 "$([[ "$SP_HYPR" == skip ]] && echo 0 || echo 1)"
    if ! (sp_deploy_quickshell "$SP_RICE"); then
        sp_rollback_failed_deployment 'Quickshell deployment failed.'
    fi
    if [[ "$SP_HYPR" != skip ]] && ! (sp_integrate_hyprland "$SP_HYPR_SOURCE"); then
        sp_rollback_failed_deployment 'Hyprland integration failed.'
    fi
    if ! (sp_check_all); then
        sp_rollback_failed_deployment 'Post-deployment runtime validation failed; Quickshell activation was skipped.'
    fi
    sp_service_transaction_begin
    if ! sp_setup_services; then
        sp_rollback_failed_deployment 'A systemd service action failed and its partial state could not be reverted.'
    fi
    if ! sp_activate_sekaipop; then
        sp_rollback_failed_deployment 'Quickshell activation failed after deployment validation.'
    fi
    if ! (sp_write_state_manifest); then
        sp_rollback_failed_deployment 'Could not write the installer state manifest.'
    fi
    sp_service_transaction_commit
    SP_QS_INSTANCE_STARTED_BY_INSTALL=0
    SP_QS_PREVIOUS_INSTANCE_WAS_RUNNING=0
    sp_ok 'SekaiPop deployment phase completed.'
}
sp_dependency_only_setup() {
    [[ "$SP_HYPR" != full ]] || sp_find_rice_source
    sp_create_backup 0 "$([[ "$SP_HYPR" == skip ]] && echo 0 || echo 1)"
    sp_service_transaction_begin
    if [[ "$SP_HYPR" != skip ]] && ! (sp_integrate_hyprland "${SP_HYPR_SOURCE:-$SP_ROOT/hypr}"); then
        sp_rollback_failed_dependency_only 'Hyprland dependency-only integration failed.'
    fi
    if ! sp_setup_services; then
        sp_rollback_failed_dependency_only 'A dependency-only systemd service action failed and its partial state could not be reverted.'
    fi
    if ! (sp_write_state_manifest); then
        sp_rollback_failed_dependency_only 'Could not write the installer state manifest in dependency-only mode.'
    fi
    sp_service_transaction_commit
}
sp_acquire_installer_lock() {
    local lock_dir lock_file
    command -v flock >/dev/null 2>&1 || sp_die 'flock is required to prevent concurrent installer transactions.'
    if [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" && ! -L "$XDG_RUNTIME_DIR" && -O "$XDG_RUNTIME_DIR" ]]; then
        lock_dir="$XDG_RUNTIME_DIR"
    else
        lock_dir="$HOME/.cache/sekaipop"
        [[ ! -L "$lock_dir" ]] || sp_die "Refusing symlinked installer lock directory: $lock_dir"
        mkdir -p -- "$lock_dir" || sp_die "Cannot create installer lock directory: $lock_dir"
        [[ -d "$lock_dir" && -O "$lock_dir" ]] || sp_die "Installer lock directory must be owned by the current user: $lock_dir"
        chmod 0700 "$lock_dir" || sp_die "Cannot secure installer lock directory: $lock_dir"
    fi
    lock_file="$lock_dir/installer.lock"
    [[ ! -L "$lock_file" ]] || sp_die "Refusing symlinked installer lock file: $lock_file"
    ( umask 077; : >> "$lock_file" ) || sp_die "Cannot create installer lock file: $lock_file"
    exec {SP_INSTALLER_LOCK_FD}> "$lock_file" || sp_die "Cannot open installer lock file: $lock_file"
    flock -n "$SP_INSTALLER_LOCK_FD" || sp_die 'Another SekaiPop installer transaction is already running. Wait for it to finish before retrying.'
}

sekaipop_main() {
    sp_parse_args "$@"
    if (( SP_RESTORE )); then sp_require_normal_user; sp_acquire_installer_lock; sp_restore_latest; return $?; fi
    sp_detect_distribution
    if (( SP_SYSTEM_UPGRADE )) && [[ "$SP_BACKEND" != arch ]]; then sp_die '--system-upgrade is only available on Arch Linux, EndeavourOS, and CachyOS.' 2; fi
    if (( SP_CHECK )); then sp_load_package_manager; sp_check_all; return $?; fi
    (( SP_DRY_RUN )) || sp_validate_preflight
    (( SP_DRY_RUN || SP_CHECK )) || sp_acquire_installer_lock
    sp_make_log
    sp_info "Detected $SP_DISTRO_NAME | ID=$SP_DISTRO_ID | backend=$SP_BACKEND | release policy=$SP_RELEASE_POLICY"
    if (( ! SP_NO_DEPS )); then
        if ! sp_plan_and_install_dependencies; then
            sp_error 'Dependency planning/installation failed; deployment was not started.'
            return 1
        fi
    fi
    if (( SP_DEPS_ONLY )); then
        sp_info 'Dependency-only mode: application source deployment is skipped.'
        if (( ! SP_DRY_RUN )); then
            if ! sp_check_all; then
                sp_error 'Dependency-only runtime verification failed; desktop integration was not started.'
                return 1
            fi
            sp_dependency_only_setup
        fi
        return 0
    fi
    if (( SP_DRY_RUN )); then
        sp_info 'Deployment plan:'
        sp_info "  Quickshell destination: $SP_QS_DEST (staged replacement; preserves settings, presets, custom data; does not touch ~/.local/state/sekaipop)"
        sp_info "  Hyprland destination: $SP_HYPR_DEST (mode=$SP_HYPR; existing config snapshot before modifications)"
        sp_info '  Services: inspect existing systemd units; only enable existing, currently inactive/disabled units after confirmation.'
        sp_info '  Activation: manage only the Quickshell instance addressed by its config path.'
        [[ -d "$SP_ROOT/sekaipop" ]] || sp_warn 'This uploaded installer bundle does not include sekaipop/; full deployment requires the complete SekaiPop source checkout or --rice DIR.'
        return 0
    fi
    (( SP_NO_DEPS )) && sp_info 'Package transactions skipped (--no-deps); post-install verification will still run.'
    sp_deploy_application
}
