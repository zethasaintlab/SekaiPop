#!/usr/bin/env bash
SP_BACKUP_ROOT="$SP_STATE_DIR/installer-backups"
sp_latest_backup_dir() {
    [[ -d "$SP_BACKUP_ROOT" ]] || return 1
    find "$SP_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -v '^restore-' | sort | tail -n1 | while IFS= read -r name; do [[ -n "$name" ]] && printf '%s/%s\n' "$SP_BACKUP_ROOT" "$name"; done
}
sp_manifest_value() { local manifest="$1" key="$2"; awk -F= -v wanted="$key" '$1 == wanted {sub(/^[^=]*=/, ""); print; exit}' "$manifest" 2>/dev/null; }
sp_tree_content_equal() {
    local left="$1" right="$2"
    [[ -d "$left" && -d "$right" ]] || return 1
    sp_have diff || return 1
    diff -qr -- "$left" "$right" >/dev/null 2>&1 || return 1
    # Content equality alone is insufficient for a rollback snapshot: executable
    # bits, private config permissions, symlink targets, empty directories and
    # mtimes are part of the filesystem state restored by cp -a.
    cmp -s \
        <(cd "$left" && find . -printf '%P\0%y\0%m\0%s\0%T@\0%l\0' | LC_ALL=C sort -z) \
        <(cd "$right" && find . -printf '%P\0%y\0%m\0%s\0%T@\0%l\0' | LC_ALL=C sort -z)
}
sp_create_backup() {
    local include_qs="${1:-1}" include_hypr="${2:-1}" backup_dir latest
    local latest_qs_included latest_hypr_included latest_qs_exists latest_hypr_exists
    local current_qs_exists=current-no current_hypr_exists=current-no same=1
    [[ "$include_qs" == 0 || "$include_qs" == 1 ]] || sp_die 'Internal backup error: invalid Quickshell scope.'
    [[ "$include_hypr" == 0 || "$include_hypr" == 1 ]] || sp_die 'Internal backup error: invalid Hyprland scope.'
    if [[ "$include_qs" == 0 && "$include_hypr" == 0 ]]; then SP_BACKUP_DIR=''; return 0; fi
    [[ ! -L "$SP_QS_DEST" || "$include_qs" != 1 ]] || sp_die "Refusing to snapshot symlinked Quickshell destination: $SP_QS_DEST"
    [[ ! -L "$SP_HYPR_DEST" || "$include_hypr" != 1 ]] || sp_die "Refusing to snapshot symlinked Hyprland destination: $SP_HYPR_DEST"
    [[ ! -L "$SP_BACKUP_ROOT" ]] || sp_die "Refusing symlinked installer backup directory: $SP_BACKUP_ROOT"
    mkdir -p "$SP_BACKUP_ROOT"
    [[ ! -e "$SP_QS_DEST" ]] || current_qs_exists=current-yes
    [[ ! -e "$SP_HYPR_DEST" ]] || current_hypr_exists=current-yes
    latest="$(sp_latest_backup_dir || true)"
    if [[ -n "$latest" && -f "$latest/manifest" ]]; then
        latest_qs_included="$(sp_manifest_value "$latest/manifest" quickshell_included)"
        latest_hypr_included="$(sp_manifest_value "$latest/manifest" hyprland_included)"
        latest_qs_exists="$(sp_manifest_value "$latest/manifest" quickshell_exists)"
        latest_hypr_exists="$(sp_manifest_value "$latest/manifest" hyprland_exists)"
        if [[ "$latest_qs_included" == "$([[ "$include_qs" == 1 ]] && echo yes || echo no)" && "$latest_hypr_included" == "$([[ "$include_hypr" == 1 ]] && echo yes || echo no)" ]]; then
            if [[ "$include_qs" == 1 ]]; then
                if [[ "$latest_qs_exists" == yes ]]; then [[ "$current_qs_exists" == current-yes ]] && sp_tree_content_equal "$SP_QS_DEST" "$latest/config/sekaipop" || same=0; else [[ "$current_qs_exists" == current-no ]] || same=0; fi
            fi
            if [[ "$include_hypr" == 1 ]]; then
                if [[ "$latest_hypr_exists" == yes ]]; then [[ "$current_hypr_exists" == current-yes ]] && sp_tree_content_equal "$SP_HYPR_DEST" "$latest/config/hypr" || same=0; else [[ "$current_hypr_exists" == current-no ]] || same=0; fi
            fi
            if (( same )); then SP_BACKUP_DIR="$latest"; sp_info "Existing configuration is unchanged; reusing snapshot: $latest"; return 0; fi
        fi
    fi
    backup_dir="$(mktemp -d "$SP_BACKUP_ROOT/$SP_TIMESTAMP.XXXXXX")" || sp_die 'Could not create a unique installer backup directory.'
    mkdir -p "$backup_dir/config"
    if [[ "$include_qs" == 1 && "$current_qs_exists" == current-yes ]]; then cp -a -- "$SP_QS_DEST" "$backup_dir/config/sekaipop" || { rm -rf -- "$backup_dir"; sp_die 'Could not snapshot the existing Quickshell config.'; }; fi
    if [[ "$include_hypr" == 1 && "$current_hypr_exists" == current-yes ]]; then cp -a -- "$SP_HYPR_DEST" "$backup_dir/config/hypr" || { rm -rf -- "$backup_dir"; sp_die 'Could not snapshot the existing Hyprland config.'; }; fi
    {
        printf 'timestamp=%s\n' "$SP_TIMESTAMP"
        printf 'distro=%s\n' "${SP_DISTRO_ID:-unknown}"
        printf 'version=%s\n' "${SP_DISTRO_VERSION:-unknown}"
        printf 'backend=%s\n' "${SP_BACKEND:-unknown}"
        printf 'profile=%s\n' "${SP_PROFILE:-unknown}"
        printf 'hypr_mode=%s\n' "${SP_HYPR:-unknown}"
        [[ "$include_qs" == 1 ]] && printf 'quickshell_included=yes\n' || printf 'quickshell_included=no\n'
        [[ "$include_hypr" == 1 ]] && printf 'hyprland_included=yes\n' || printf 'hyprland_included=no\n'
        [[ "$current_qs_exists" == current-yes && "$include_qs" == 1 ]] && printf 'quickshell_exists=yes\n' || printf 'quickshell_exists=no\n'
        [[ "$current_hypr_exists" == current-yes && "$include_hypr" == 1 ]] && printf 'hyprland_exists=yes\n' || printf 'hyprland_exists=no\n'
        [[ -d "$backup_dir/config/sekaipop" ]] && printf 'quickshell=yes\n' || printf 'quickshell=no\n'
        [[ -d "$backup_dir/config/hypr" ]] && printf 'hyprland=yes\n' || printf 'hyprland=no\n'
    } > "$backup_dir/manifest"
    SP_BACKUP_DIR="$backup_dir"; sp_info "Configuration snapshot saved: $backup_dir"
}
sp_restore_latest() {
    local requested_snapshot="${1:-}" latest='' candidate snapshot backup_qs backup_hypr restore_backup
    local qs_included qs_exists hypr_included hypr_exists manifest
    if [[ ! -d "$SP_BACKUP_ROOT" ]]; then
        [[ -z "$requested_snapshot" ]] && sp_restore_legacy_hypr_backup && return 0
        sp_die "The transaction backup root is missing; cannot restore requested snapshot: $requested_snapshot"
    fi
    [[ ! -L "$SP_BACKUP_ROOT" ]] || sp_die "Refusing symlinked installer backup directory: $SP_BACKUP_ROOT"
    if [[ -n "$requested_snapshot" ]]; then
        [[ "$requested_snapshot" == "$SP_BACKUP_ROOT/"* && -d "$requested_snapshot" && ! -L "$requested_snapshot" ]] ||
            sp_die "Refusing invalid transaction snapshot path: $requested_snapshot"
        snapshot="$requested_snapshot"
        latest="${snapshot##*/}"
    else
        while IFS= read -r candidate; do
            [[ "$candidate" == restore-* ]] && continue
            manifest="$SP_BACKUP_ROOT/$candidate/manifest"; [[ -f "$manifest" ]] || continue
            if [[ "$(sp_manifest_value "$manifest" quickshell_included)" == yes || "$(sp_manifest_value "$manifest" hyprland_included)" == yes || -d "$SP_BACKUP_ROOT/$candidate/config/hypr" || -d "$SP_BACKUP_ROOT/$candidate/config/sekaipop" ]]; then latest="$candidate"; fi
        done < <(find "$SP_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
        if [[ -z "$latest" ]]; then sp_restore_legacy_hypr_backup; return $?; fi
        snapshot="$SP_BACKUP_ROOT/$latest"
    fi
    manifest="$snapshot/manifest"; backup_hypr="$snapshot/config/hypr"; backup_qs="$snapshot/config/sekaipop"
    [[ -f "$manifest" && ! -L "$manifest" ]] || sp_die "Snapshot manifest is missing, unreadable, or symlinked: $manifest"
    [[ ! -L "$snapshot/config" ]] || sp_die "Refusing symlinked snapshot config directory: $snapshot/config"
    qs_included="$(sp_manifest_value "$manifest" quickshell_included)"; hypr_included="$(sp_manifest_value "$manifest" hyprland_included)"
    qs_exists="$(sp_manifest_value "$manifest" quickshell_exists)"; hypr_exists="$(sp_manifest_value "$manifest" hyprland_exists)"
    for value in "$qs_included" "$hypr_included" "$qs_exists" "$hypr_exists"; do
        [[ -z "$value" || "$value" == yes || "$value" == no ]] || sp_die "Snapshot manifest contains an invalid scope value: $value"
    done
    if [[ -z "$qs_included" ]]; then qs_included=no; [[ -d "$backup_qs" ]] && qs_included=yes; fi
    if [[ -z "$hypr_included" ]]; then hypr_included=no; [[ -d "$backup_hypr" ]] && hypr_included=yes; fi
    if [[ -z "$qs_exists" ]]; then qs_exists=no; [[ -d "$backup_qs" ]] && qs_exists=yes; fi
    if [[ -z "$hypr_exists" ]]; then hypr_exists=no; [[ -d "$backup_hypr" ]] && hypr_exists=yes; fi
    if [[ "$qs_included" == yes && "$qs_exists" == yes ]]; then
        [[ -d "$backup_qs" && ! -L "$backup_qs" ]] || sp_die "Quickshell snapshot content is missing or symlinked: $backup_qs"
    fi
    if [[ "$hypr_included" == yes && "$hypr_exists" == yes ]]; then
        [[ -d "$backup_hypr" && ! -L "$backup_hypr" ]] || sp_die "Hyprland snapshot content is missing or symlinked: $backup_hypr"
    fi
    [[ "$qs_included" != no || "$qs_exists" != yes ]] || sp_die 'Snapshot manifest marks Quickshell as existing outside its included restore scope.'
    [[ "$hypr_included" != no || "$hypr_exists" != yes ]] || sp_die 'Snapshot manifest marks Hyprland as existing outside its included restore scope.'
    sp_info "Restore source: $snapshot"
    sp_confirm 'Restore this snapshot? Current destinations will first be preserved in a separate recovery snapshot.' || sp_die 'Restore cancelled.'
    restore_backup="$(mktemp -d "$SP_BACKUP_ROOT/restore-$SP_TIMESTAMP.XXXXXX")" || sp_die 'Could not create a recovery snapshot before restore.'
    mkdir -p "$restore_backup/config" || { rm -rf -- "$restore_backup"; sp_die 'Could not prepare the recovery snapshot directory.'; }
    if [[ -e "$SP_QS_DEST" || -L "$SP_QS_DEST" ]]; then
        cp -a -- "$SP_QS_DEST" "$restore_backup/config/sekaipop-current" ||
            { rm -rf -- "$restore_backup"; sp_die "Could not preserve the current Quickshell configuration; nothing was restored. Destination: $SP_QS_DEST"; }
    fi
    if [[ -e "$SP_HYPR_DEST" || -L "$SP_HYPR_DEST" ]]; then
        cp -a -- "$SP_HYPR_DEST" "$restore_backup/config/hypr-current" ||
            { rm -rf -- "$restore_backup"; sp_die "Could not preserve the current Hyprland configuration; nothing was restored. Destination: $SP_HYPR_DEST"; }
    fi
    printf 'source_snapshot=%s\nrestored_at=%s\nquickshell_current_exists=%s\nhyprland_current_exists=%s\n' \
        "$latest" "$SP_TIMESTAMP" "$([[ -e "$restore_backup/config/sekaipop-current" || -L "$restore_backup/config/sekaipop-current" ]] && echo yes || echo no)" \
        "$([[ -e "$restore_backup/config/hypr-current" || -L "$restore_backup/config/hypr-current" ]] && echo yes || echo no)" > "$restore_backup/manifest" ||
        { rm -rf -- "$restore_backup"; sp_die 'Could not write the recovery snapshot manifest; nothing was restored.'; }
    if [[ "$qs_included" == yes ]]; then
        if [[ "$qs_exists" == yes ]]; then [[ -d "$backup_qs" ]] || sp_die 'Quickshell snapshot manifest is inconsistent; refusing restore.'; sp_replace_tree "$backup_qs" "$SP_QS_DEST" || sp_die 'Quickshell restore failed.'
        elif [[ -e "$SP_QS_DEST" || -L "$SP_QS_DEST" ]]; then [[ ! -L "$SP_QS_DEST" ]] || sp_die "Refusing to remove symlinked Quickshell destination: $SP_QS_DEST"; rm -rf -- "$SP_QS_DEST" || sp_die 'Could not restore the original absence of the Quickshell destination.'; fi
    fi
    if [[ "$hypr_included" == yes ]]; then
        if [[ "$hypr_exists" == yes ]]; then [[ -d "$backup_hypr" ]] || sp_die 'Hyprland snapshot manifest is inconsistent; refusing restore.'; sp_replace_tree "$backup_hypr" "$SP_HYPR_DEST" || sp_die 'Hyprland restore failed.'
        elif [[ -e "$SP_HYPR_DEST" || -L "$SP_HYPR_DEST" ]]; then [[ ! -L "$SP_HYPR_DEST" ]] || sp_die "Refusing to remove symlinked Hyprland destination: $SP_HYPR_DEST"; rm -rf -- "$SP_HYPR_DEST" || sp_die 'Could not restore the original absence of the Hyprland destination.'; fi
    fi
    sp_ok "Restore completed. The previous current configs are retained at $restore_backup."
}
sp_restore_legacy_hypr_backup() {
    local candidate latest='' restore_backup
    for candidate in "$SP_CONFIG_HOME"/hypr.sekaipop-backup-* "$SP_CONFIG_HOME"/hypr.pjsekai-backup-*; do
        [[ -d "$candidate" && ! -L "$candidate" ]] || continue
        [[ -z "$latest" || "$candidate" > "$latest" ]] && latest="$candidate"
    done
    [[ -n "$latest" ]] || sp_die "No installer snapshot or legacy hypr.sekaipop-backup-* directory was found."
    sp_info "Legacy upstream Hyprland backup: $latest"
    sp_confirm 'Restore this legacy Hyprland backup? The current config will be saved separately.' || sp_die 'Legacy restore cancelled.'
    mkdir -p "$SP_BACKUP_ROOT"; [[ ! -L "$SP_BACKUP_ROOT" ]] || sp_die "Refusing symlinked installer backup directory: $SP_BACKUP_ROOT"
    restore_backup="$(mktemp -d "$SP_BACKUP_ROOT/restore-legacy-$SP_TIMESTAMP.XXXXXX")" || sp_die 'Could not create recovery snapshot for legacy restore.'
    mkdir -p "$restore_backup/config"; [[ ! -e "$SP_HYPR_DEST" ]] || cp -a -- "$SP_HYPR_DEST" "$restore_backup/config/hypr-current"
    sp_replace_tree "$latest" "$SP_HYPR_DEST" || sp_die 'Legacy Hyprland restore failed.'
    printf 'legacy_source=%s\nrestored_at=%s\n' "$latest" "$SP_TIMESTAMP" > "$restore_backup/manifest"
    sp_ok "Legacy Hyprland configuration restored. Previous current config is retained at $restore_backup."
}
sp_replace_tree() {
    local source="$1" destination="$2" parent stage old
    [[ ! -L "$destination" ]] || sp_die "Refusing to restore over symlinked destination: $destination"
    parent="$(dirname "$destination")"; mkdir -p "$parent"
    stage="$(mktemp -d "$parent/.sekaipop-restore.XXXXXX")"
    cp -a "$source/." "$stage/" || { rm -rf -- "$stage"; return 1; }
    old="${destination}.restore-old-$SP_TIMESTAMP"
    if [[ -e "$destination" ]]; then mv -- "$destination" "$old" || { rm -rf -- "$stage"; return 1; }; fi
    if mv -- "$stage" "$destination"; then [[ ! -e "$old" ]] || rm -rf -- "$old"
    else [[ -e "$old" && ! -e "$destination" ]] && mv -- "$old" "$destination"; rm -rf -- "$stage"; return 1; fi
}
