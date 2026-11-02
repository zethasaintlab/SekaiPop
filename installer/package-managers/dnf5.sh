#!/usr/bin/env bash

pm_detect() {
    [[ -n "${SP_DNF_BIN:-}" ]] || sp_die 'DNF5 executable was not selected during distribution detection.'
    "$SP_DNF_BIN" --version >/dev/null 2>&1 || sp_die 'DNF5 failed its version check.'
    sp_have rpm || sp_die 'rpm query utility is required by the DNF5 backend.'
}
pm_query_installed() { rpm -q -- "$1" >/dev/null 2>&1; }
pm_query_available() {
    "$SP_DNF_BIN" repoquery --available --cacheonly --qf '%{name}' "$1" 2>/dev/null | grep -Fxq -- "$1"
}
pm_query_provider() { "$SP_DNF_BIN" repoquery --whatprovides --cacheonly --qf '%{name}' "$1" 2>/dev/null | sort -u; }
pm_refresh_metadata() { sp_sudo "$SP_DNF_BIN" makecache --refresh; }
pm_install() {
    local -a args=(install)
    (( SP_YES )) && args+=(-y)
    sp_sudo "$SP_DNF_BIN" "${args[@]}" -- "$@"
}
pm_get_package_version() {
    if pm_query_installed "$1"; then rpm -q --qf '%{VERSION}-%{RELEASE}\n' -- "$1" 2>/dev/null
    else "$SP_DNF_BIN" repoquery --available --cacheonly --qf '%{version}-%{release}' "$1" 2>/dev/null | head -n1; fi
}
pm_get_package_owner() { rpm -qf -- "$1" 2>/dev/null; }
