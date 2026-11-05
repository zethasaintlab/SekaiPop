#!/usr/bin/env bash
# Read-only validation of official APT repositories required by supported profiles.
# SekaiPop never edits APT sources, adds repositories, or imports signing keys.
SP_APT_SOURCES_DIR="${SP_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
SP_APT_MAIN_SOURCES="${SP_APT_MAIN_SOURCES:-/etc/apt/sources.list}"
sp_apt_sources_has_suite_component() {
    local suite="$1" component="$2" wanted_uris="${3:-}" file old_nullglob=0
    shopt -q nullglob && old_nullglob=1
    shopt -s nullglob
    local -a files=("$SP_APT_SOURCES_DIR"/*.list "$SP_APT_SOURCES_DIR"/*.sources "$SP_APT_MAIN_SOURCES")
    (( old_nullglob )) || shopt -u nullglob
    for file in "${files[@]}"; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        if [[ "$file" == *.sources ]]; then
            awk -v wanted_suite="$suite" -v wanted_component="$component" -v wanted_uris="$wanted_uris" '
                BEGIN { RS = ""; FS = "\n"; expected_count = split(wanted_uris, expected, /[[:space:]]+/) }
                {
                    suites = components = uris = ""; enabled = "yes"; field = ""
                    for (i = 1; i <= NF; i++) {
                        line = $i; sub(/\r$/, "", line)
                        if (line ~ /^[[:space:]]/) {
                            value = line; sub(/^[[:space:]]+/, "", value)
                            if (field == "suites") suites = suites " " value
                            else if (field == "components") components = components " " value
                            else if (field == "uris") uris = uris " " value
                            else if (field == "enabled") enabled = tolower(value)
                            continue
                        }
                        colon = index(line, ":")
                        if (!colon) { field = ""; continue }
                        field = tolower(substr(line, 1, colon - 1))
                        value = substr(line, colon + 1); sub(/^[[:space:]]+/, "", value)
                        if (field == "suites") suites = value
                        else if (field == "components") components = value
                        else if (field == "uris") uris = value
                        else if (field == "enabled") enabled = tolower(value)
                    }
                    if (enabled == "no") next
                    if (wanted_uris != "") {
                        nu = split(uris, uri_tokens, /[[:space:]]+/); uri_found = 0
                        for (i = 1; i <= nu; i++) for (j = 1; j <= expected_count; j++) if (uri_tokens[i] == expected[j]) uri_found = 1
                        if (!uri_found) next
                    }
                    ns = split(suites, suite_tokens, /[[:space:]]+/)
                    nc = split(components, component_tokens, /[[:space:]]+/)
                    suite_found = component_found = 0
                    for (i = 1; i <= ns; i++) if (suite_tokens[i] == wanted_suite) suite_found = 1
                    for (i = 1; i <= nc; i++) if (component_tokens[i] == wanted_component) component_found = 1
                    if (suite_found && component_found) found = 1
                }
                END { exit !found }
            ' "$file" && return 0
        else
            awk -v wanted_suite="$suite" -v wanted_component="$component" -v wanted_uris="$wanted_uris" '
                BEGIN { expected_count = split(wanted_uris, expected, /[[:space:]]+/) }
                /^[[:space:]]*#/ { next }
                $1 == "deb" || $1 == "deb-src" {
                    i = 2
                    if ($i ~ /^\[/) { while (i <= NF && $i !~ /\]$/) i++; i++ }
                    source_uri = $(i); source_suite = $(i + 1)
                    uri_found = (wanted_uris == "")
                    for (j = 1; j <= expected_count; j++) if (source_uri == expected[j]) uri_found = 1
                    if (uri_found && source_suite == wanted_suite) for (j = i + 2; j <= NF; j++) if ($j == wanted_component) found = 1
                }
                END { exit !found }
            ' "$file" && return 0
        fi
    done
    return 1
}
sp_apt_report_required_sources() {
    local codename="${SP_DISTRO_CODENAME:-}"
    case "${SP_DISTRO_ID:-}" in
        debian)
            if [[ "${SP_DISTRO_VERSION:-}" == 13 ]] && ! sp_apt_sources_has_suite_component trixie-backports main 'https://deb.debian.org/debian http://deb.debian.org/debian'; then
                sp_warn 'Required repository missing: configure official Debian 13 trixie-backports (main) before installation. SekaiPop will not modify APT sources.'
            fi ;;
        ubuntu)
            if [[ "${SP_DISTRO_VERSION:-}" == 26.10 ]] &&
                { ! sp_apt_sources_has_suite_component "$codename" universe 'https://archive.ubuntu.com/ubuntu http://archive.ubuntu.com/ubuntu' ||
                  ! sp_apt_sources_has_suite_component "$codename-updates" universe 'https://archive.ubuntu.com/ubuntu http://archive.ubuntu.com/ubuntu' ||
                  ! sp_apt_sources_has_suite_component "$codename-security" universe 'https://security.ubuntu.com/ubuntu http://security.ubuntu.com/ubuntu'; }; then
                sp_warn "Required repository missing: configure official Ubuntu Universe for $codename, updates, and security before installation. SekaiPop will not modify APT sources."
            fi ;;
    esac
}
sp_apt_validate_required_sources() {
    local codename="${SP_DISTRO_CODENAME:-}"
    [[ "${SP_BACKEND:-}" == apt ]] || return 0
    case "${SP_DISTRO_ID:-}" in
        debian)
            [[ "${SP_DISTRO_VERSION:-}" == 13 && "$codename" == trixie ]] || return 0
            sp_apt_sources_has_suite_component trixie-backports main 'https://deb.debian.org/debian http://deb.debian.org/debian' ||
                sp_die 'Official Debian 13 trixie-backports (main) is not configured. Configure the official Debian archive and system archive keyring manually, run apt update, then retry. SekaiPop will not create or modify APT source files.'
            sp_info 'Official Debian trixie-backports main component is configured.' ;;
        ubuntu)
            [[ "${SP_DISTRO_VERSION:-}" == 26.10 ]] || return 0
            [[ "$codename" =~ ^[a-z][a-z0-9-]*$ ]] || sp_die 'Ubuntu release codename is missing or invalid; refusing repository validation.'
            sp_apt_sources_has_suite_component "$codename" universe 'https://archive.ubuntu.com/ubuntu http://archive.ubuntu.com/ubuntu' &&
                sp_apt_sources_has_suite_component "$codename-updates" universe 'https://archive.ubuntu.com/ubuntu http://archive.ubuntu.com/ubuntu' &&
                sp_apt_sources_has_suite_component "$codename-security" universe 'https://security.ubuntu.com/ubuntu http://security.ubuntu.com/ubuntu' ||
                sp_die "Official Ubuntu Universe is not configured for $codename, updates, and security. Enable Universe using Ubuntu's supported system tools, run apt update, then retry. SekaiPop will not create or modify APT source files."
            sp_info 'Official Ubuntu Universe is configured for release, updates, and security suites.' ;;
    esac
}
