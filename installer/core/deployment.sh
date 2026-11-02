#!/usr/bin/env bash
sp_preserve_path() { local source="$1" target="$2"; [[ -e "$source" || -L "$source" ]] || return 0; mkdir -p "$(dirname "$target")"; cp -a -- "$source" "$target"; }
sp_deploy_quickshell() {
    local source="$1" parent stage old item
    [[ -d "$source" && -f "$source/shell.qml" ]] || sp_die "SekaiPop source directory is incomplete: $source (shell.qml is required)."
    [[ ! -L "$SP_QS_DEST" ]] || sp_die "Refusing to replace symlinked Quickshell destination: $SP_QS_DEST"
    mkdir -p "$(dirname "$SP_QS_DEST")"; parent="$(dirname "$SP_QS_DEST")"
    stage="$(mktemp -d "$parent/.sekaipop-stage.XXXXXX")"
    if ! cp -a "$source/." "$stage/"; then rm -rf -- "$stage"; sp_die 'Could not stage SekaiPop source files.'; fi
    rm -rf -- "$stage/.git"; (( SP_WITH_TESTS )) || rm -rf -- "$stage/tests"
    for item in settings presets custom custom-images history; do
        if [[ -e "$SP_QS_DEST/$item" || -L "$SP_QS_DEST/$item" ]]; then rm -rf -- "$stage/$item"; sp_preserve_path "$SP_QS_DEST/$item" "$stage/$item"; fi
    done
    for item in settings.json user_config.json; do
        if [[ -e "$SP_QS_DEST/$item" || -L "$SP_QS_DEST/$item" ]]; then rm -f -- "$stage/$item"; sp_preserve_path "$SP_QS_DEST/$item" "$stage/$item"; fi
    done
    if ! (sp_prepare_shaders "$stage/shaders"); then
        rm -rf -- "$stage"
        sp_die 'Shader preparation failed in the staged Quickshell tree; the current installation was not replaced.'
    fi
    if sp_have git && git -C "$source" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        { printf 'commit=%s\n' "$(git -C "$source" rev-parse HEAD 2>/dev/null || echo unknown)"; printf 'repo=%s\n' "$(git -C "$source" config --get remote.origin.url 2>/dev/null || echo unknown)"; printf 'ref=%s\n' "$(git -C "$source" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"; } > "$stage/.source"
    fi
    old="${SP_QS_DEST}.sekaipop-old-$SP_TIMESTAMP"
    if [[ -e "$SP_QS_DEST" ]]; then mv -- "$SP_QS_DEST" "$old" || { rm -rf -- "$stage"; sp_die 'Could not preserve the current Quickshell config for atomic deployment.'; }; fi
    if mv -- "$stage" "$SP_QS_DEST"; then [[ ! -e "$old" ]] || rm -rf -- "$old"; sp_ok "SekaiPop deployed to $SP_QS_DEST. Existing user state and presets were preserved."
    else [[ -e "$old" && ! -e "$SP_QS_DEST" ]] && mv -- "$old" "$SP_QS_DEST"; rm -rf -- "$stage"; sp_die 'Quickshell deployment failed; the previous config was restored.'; fi
}
sp_qs_instance_state() {
    local output
    sp_have qs || return 2
    output="$(qs list -p "$SP_QS_DEST" 2>/dev/null)" || return 2
    [[ -n "$output" ]] || return 2
    grep -qi 'No running instances' <<< "$output" && return 1
    return 0
}
sp_activate_sekaipop() {
    local attempt=0 state=2
    [[ "$SP_HYPR" != skip ]] || return 0
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || { sp_info 'No active Hyprland session; SekaiPop can start at the next login.'; return 0; }
    sp_have qs || { sp_warn 'qs is unavailable; activation skipped.'; return 0; }
    if sp_qs_instance_state; then state=0; else state=$?; fi
    case "$state" in
        0)
            sp_confirm 'Restart the running SekaiPop instance addressed by its config path?' || { sp_info 'Existing SekaiPop instance left running.'; return 0; }
            qs kill -p "$SP_QS_DEST" >/dev/null 2>&1 || { sp_warn 'Quickshell did not accept the path-scoped kill request.'; return 1; }
            while (( attempt < 50 )); do if sp_qs_instance_state; then state=0; else state=$?; fi; [[ "$state" == 1 ]] && break; sleep 0.1; attempt=$((attempt + 1)); done
            [[ "$state" == 1 ]] || { sp_warn 'Could not confirm that the SekaiPop instance stopped; refusing to start a duplicate.'; return 1; }
            ;;
        1) sp_confirm 'Start SekaiPop in the current Hyprland session?' || return 0 ;;
        *) sp_warn 'Quickshell instance state could not be queried reliably; refusing to start a possible duplicate.'; return 1 ;;
    esac
    qs -p "$SP_QS_DEST" -n -d >/dev/null 2>&1 || { sp_warn 'Could not activate the SekaiPop config with qs -p <path> -n -d.'; return 1; }
    sp_ok 'SekaiPop started using Quickshell path-scoped instance management.'
}
sp_find_rice_source() {
    if [[ -n "$SP_RICE" ]]; then [[ -d "$SP_RICE" ]] || sp_die "--rice directory does not exist: $SP_RICE"; SP_RICE="$(cd "$SP_RICE" && pwd -P)"
    else
        for candidate in "$SP_ROOT/sekaipop" "$SP_ROOT/../sekaipop"; do if [[ -f "$candidate/shell.qml" ]]; then SP_RICE="$(cd "$candidate" && pwd -P)"; break; fi; done
    fi
    [[ -n "$SP_RICE" && -f "$SP_RICE/shell.qml" ]] || sp_die 'SekaiPop application source is absent. Use the complete SekaiPop checkout or pass --rice DIR.'
    SP_HYPR_SOURCE="$SP_ROOT/hypr"
    if [[ "$SP_HYPR" == full ]]; then [[ -d "$SP_HYPR_SOURCE" && -f "$SP_HYPR_SOURCE/hyprland.lua" ]] || sp_die "Full Hyprland source is absent: $SP_HYPR_SOURCE/hyprland.lua. Use the complete SekaiPop checkout."; fi
}
sp_write_state_manifest() {
    local manifest="$SP_STATE_DIR/installer-manifest.env"
    (( SP_DRY_RUN )) && return 0
    mkdir -p "$SP_STATE_DIR"
    {
        printf 'installer_version=%s\n' '2.1.0'
        printf 'installed_at=%s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
        printf 'distro_id=%s\n' "$SP_DISTRO_ID"
        printf 'distro_version=%s\n' "$SP_DISTRO_VERSION"
        printf 'backend=%s\n' "$SP_BACKEND"
        printf 'profile=%s\n' "$SP_PROFILE"
        printf 'hypr_mode=%s\n' "$SP_HYPR"
        printf 'packages=%q\n' "${SP_INSTALL_PKGS[*]:-}"
        printf 'backup=%q\n' "${SP_BACKUP_DIR:-}"
    } > "$manifest"
    sp_info "Installer state manifest: $manifest"
}
