#!/usr/bin/env bash

pm_detect() { sp_have apt-get && sp_have dpkg-query && sp_have apt-cache || sp_die 'APT backend is incomplete.'; }
pm_package_name() { printf '%s\n' "${1%%/*}"; }
pm_package_target() { [[ "$1" == */* ]] && printf '%s\n' "${1#*/}"; }
pm_query_installed() {
    local package
    package="$(pm_package_name "$1")"
    local status
    status="$(dpkg-query -W -f='${Status}' -- "$package" 2>/dev/null || true)"
    [[ "$status" == 'install ok installed' ]]
}
pm_query_available() {
    local package target candidate
    package="$(pm_package_name "$1")"
    target="$(pm_package_target "$1" || true)"
    if [[ -n "$target" ]]; then
        candidate="$(apt-cache -t "$target" policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    else
        candidate="$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    fi
    [[ -n "$candidate" && "$candidate" != '(none)' ]]
}
pm_query_provider() { apt-cache showpkg "$(pm_package_name "$1")" 2>/dev/null | sed -n '/Reverse Provides:/,$p' | tail -n +2; }
pm_refresh_metadata() { sp_sudo apt-get update; }
pm_install() {
    local -a args=(install --no-install-recommends)
    (( SP_YES )) && args+=(-y)
    if (( SP_YES )); then
        sp_sudo env DEBIAN_FRONTEND=noninteractive apt-get "${args[@]}" -- "$@"
    else
        sp_sudo apt-get "${args[@]}" -- "$@"
    fi
}
pm_get_package_version() {
    local package target
    package="$(pm_package_name "$1")"
    if pm_query_installed "$package"; then
        dpkg-query -W -f='${Version}\n' -- "$package" 2>/dev/null
    else
        target="$(pm_package_target "$1" || true)"
        if [[ -n "$target" ]]; then
            apt-cache -t "$target" policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}'
        else
            apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}'
        fi
    fi
}
pm_get_package_owner() { dpkg-query -S -- "$1" 2>/dev/null | head -n1; }
