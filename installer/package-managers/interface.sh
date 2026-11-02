#!/usr/bin/env bash
# Common package-manager contract: pm_detect, pm_refresh_metadata,
# pm_query_installed, pm_query_available, pm_query_provider, pm_install,
# pm_get_package_version and pm_get_package_owner.

sp_load_package_manager() {
    case "$SP_BACKEND" in
        arch) source "$SP_ROOT/installer/package-managers/pacman.sh" ;;
        dnf5) source "$SP_ROOT/installer/package-managers/dnf5.sh" ;;
        apt) source "$SP_ROOT/installer/package-managers/apt.sh" ;;
        *) sp_die "No package-manager backend for '$SP_BACKEND'." ;;
    esac
    pm_detect
}

sp_valid_package_name() {
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9+._:-]*(/[a-zA-Z0-9][a-zA-Z0-9+._:-]*)?$ ]]
}

sp_resolve_package_spec() {
    local spec="$1" candidate
    local -a candidates=()
    IFS='|' read -r -a candidates <<< "$spec"
    for candidate in "${candidates[@]}"; do
        sp_valid_package_name "$candidate" || continue
        if pm_query_installed "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
    done
    for candidate in "${candidates[@]}"; do
        sp_valid_package_name "$candidate" || continue
        if pm_query_available "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
    done
    return 1
}
