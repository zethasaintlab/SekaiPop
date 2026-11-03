#!/usr/bin/env bash

pm_detect() { sp_have pacman || sp_die 'pacman backend selected but pacman is missing.'; }
pm_query_installed() { pacman -Q -- "$1" >/dev/null 2>&1; }
pm_query_available() { pacman -Si -- "$1" >/dev/null 2>&1; }
pm_query_provider() { pacman -Fq -- "$1" 2>/dev/null; }
pm_refresh_metadata() {
    # Never run pacman -Sy alone. Repository refresh is only part of a full upgrade.
    (( SP_SYSTEM_UPGRADE )) || sp_die 'Refusing pacman -Sy. On Arch, authorize a full synchronization transaction with --system-upgrade.'
    local -a args=(-Syu --needed)
    (( SP_YES )) && args+=(--noconfirm)
    sp_sudo pacman "${args[@]}"
    SP_ARCH_SYNC_UPGRADED=1
}
pm_install() {
    local -a args=(--needed)
    (( SP_YES )) && args+=(--noconfirm)
    if (( ${SP_ARCH_SYNC_UPGRADED:-0} )); then
        # A previous -Syu in this invocation refreshed the databases and upgraded the host.
        sp_sudo pacman -S "${args[@]}" -- "$@"
    elif (( SP_SYSTEM_UPGRADE )); then
        sp_sudo pacman -Syu "${args[@]}" -- "$@"
    else
        sp_sudo pacman -S "${args[@]}" -- "$@" || {
            sp_error 'pacman transaction failed. No isolated database refresh was attempted; review the system and use --system-upgrade only when you authorize a full upgrade.'
            return 1
        }
    fi
}
pm_get_package_version() {
    local version
    if pacman -Q -- "$1" >/dev/null 2>&1; then
        pacman -Q -- "$1" 2>/dev/null | awk '{print $2}'
    else
        version="$(pacman -Si -- "$1" 2>/dev/null | awk -F: '$1 ~ /^Version[[:space:]]*$/ {sub(/^[[:space:]]*/, "", $2); print $2; exit}')"
        [[ -n "$version" ]] && printf '%s\n' "$version"
    fi
}
pm_get_package_owner() { pacman -Qo -- "$1" 2>/dev/null | sed -E 's/ is owned by / /'; }
