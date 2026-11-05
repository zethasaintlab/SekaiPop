#!/usr/bin/env bash
# Provision only official distribution repositories required by supported APT profiles.
# This module never adds PPAs, third-party archives, mirrors, or package signing keys.

SP_APT_SOURCES_DIR="${SP_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
SP_APT_MAIN_SOURCES="${SP_APT_MAIN_SOURCES:-/etc/apt/sources.list}"
declare -ag SP_APT_BOOTSTRAP_CREATED=()
declare -ag SP_APT_BOOTSTRAP_CREATED_SHA=()

sp_apt_sources_has_suite_component() {
    local suite="$1" component="$2" file
    shopt -s nullglob
    local -a files=("$SP_APT_SOURCES_DIR"/*.list "$SP_APT_SOURCES_DIR"/*.sources "$SP_APT_MAIN_SOURCES")
    shopt -u nullglob
    for file in "${files[@]}"; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        if [[ "$file" == *.sources ]]; then
            awk -v wanted_suite="$suite" -v wanted_component="$component" '
                BEGIN { RS = ""; FS = "\n" }
                {
                    suites = ""
                    components = ""
                    enabled = "yes"
                    for (i = 1; i <= NF; i++) {
                        line = $i
                        sub(/^[[:space:]]+/, "", line)
                        if (line ~ /^#/) continue
                        if (line ~ /^Suites:[[:space:]]*/) {
                            sub(/^Suites:[[:space:]]*/, "", line)
                            suites = line
                        } else if (line ~ /^Components:[[:space:]]*/) {
                            sub(/^Components:[[:space:]]*/, "", line)
                            components = line
                        } else if (line ~ /^Enabled:[[:space:]]*/) {
                            sub(/^Enabled:[[:space:]]*/, "", line)
                            enabled = tolower(line)
                        }
                    }
                    if (enabled == "no") next
                    ns = split(suites, suite_tokens, /[[:space:]]+/)
                    nc = split(components, component_tokens, /[[:space:]]+/)
                    suite_found = 0
                    component_found = 0
                    for (i = 1; i <= ns; i++) if (suite_tokens[i] == wanted_suite) suite_found = 1
                    for (i = 1; i <= nc; i++) if (component_tokens[i] == wanted_component) component_found = 1
                    if (suite_found && component_found) found = 1
                }
                END { exit !found }
            ' "$file" && return 0
        else
            awk -v wanted_suite="$suite" -v wanted_component="$component" '
                /^[[:space:]]*#/ { next }
                $1 == "deb" || $1 == "deb-src" {
                    i = 2
                    if ($i ~ /^\[/) {
                        while (i <= NF && $i !~ /\]$/) i++
                        i++
                    }
                    source_suite = $(i + 1)
                    if (source_suite == wanted_suite) {
                        for (j = i + 2; j <= NF; j++) if ($j == wanted_component) found = 1
                    }
                }
                END { exit !found }
            ' "$file" && return 0
        fi
    done
    return 1
}

sp_apt_managed_source_write() {
    local target="$1" content="$2" marker='# Managed by SekaiPop Universal Installer; official distribution archive only.'
    local tmp stage expected_sha actual_sha
    [[ "$target" == "$SP_APT_SOURCES_DIR/"* ]] || sp_die "Refusing APT source path outside the configured sources directory: $target"
    [[ ! -L "$target" ]] || sp_die "Refusing to replace symlinked APT source file: $target"
    tmp="$(mktemp)"
    printf '%s\n%s\n' "$marker" "$content" > "$tmp"
    if [[ -e "$target" ]]; then
        if ! grep -Fq -- "$marker" "$target"; then
            rm -f -- "$tmp"
            sp_die "APT source target already exists and is not installer-managed: $target"
        fi
        if cmp -s -- "$tmp" "$target"; then
            rm -f -- "$tmp"
            return 0
        fi
        rm -f -- "$tmp"
        sp_die "Installer-managed APT source was modified; refusing to overwrite it: $target"
    fi
    stage="$target.sekaipop-stage-$$"
    if [[ -e "$stage" || -L "$stage" ]]; then rm -f -- "$tmp"; sp_die "APT source staging path already exists: $stage"; fi
    if ! sp_sudo install -m 0644 -- "$tmp" "$stage"; then
        rm -f -- "$tmp"
        sp_die "Could not stage official APT source file: $target"
    fi
    rm -f -- "$tmp"
    if ! sp_sudo mv -- "$stage" "$target"; then
        sp_sudo rm -f -- "$stage" || true
        sp_die "Could not atomically activate official APT source file: $target"
    fi
    expected_sha="$(sha256sum -- "$target" | awk '{print $1}')"
    SP_APT_BOOTSTRAP_CREATED+=("$target")
    SP_APT_BOOTSTRAP_CREATED_SHA+=("$expected_sha")
    sp_ok "Enabled official APT source: $target"
}

sp_apt_bootstrap_plan() {
    local codename="${SP_DISTRO_CODENAME:-stonking}"
    case "${SP_DISTRO_ID:-}" in
        debian)
            if [[ "${SP_DISTRO_VERSION:-}" == 13 ]] && ! sp_apt_sources_has_suite_component trixie-backports main; then
                sp_info 'Repository bootstrap required: official Debian trixie-backports (main).'
            fi
            ;;
        ubuntu)
            if [[ "${SP_DISTRO_VERSION:-}" == 26.10 ]] &&
                { ! sp_apt_sources_has_suite_component "$codename" universe ||
                  ! sp_apt_sources_has_suite_component "$codename-updates" universe ||
                  ! sp_apt_sources_has_suite_component "$codename-security" universe; }; then
                sp_info "Repository bootstrap required: official Ubuntu Universe for $codename, updates, and security."
            fi
            ;;
    esac
}

sp_apt_bootstrap_official_sources() {
    local codename components missing_archive_suites missing_security source_content
    SP_APT_BOOTSTRAP_CREATED=()
    SP_APT_BOOTSTRAP_CREATED_SHA=()
    [[ "${SP_BACKEND:-}" == apt ]] || return 0
    case "${SP_DISTRO_ID:-}" in
        debian)
            [[ "${SP_DISTRO_VERSION:-}" == 13 && "${SP_DISTRO_CODENAME:-}" == trixie ]] || return 0
            if ! sp_apt_sources_has_suite_component trixie-backports main; then
                sp_confirm 'Enable the official Debian 13 trixie-backports repository? This adds only the signed Debian archive source.' ||
                    sp_die 'Debian backports activation declined; no APT source was changed.'
                sp_apt_managed_source_write "$SP_APT_SOURCES_DIR/sekaipop-trixie-backports.sources" \
                    'Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg'
            else
                sp_info 'Official Debian trixie-backports main component is already configured.'
            fi
            ;;
        ubuntu)
            [[ "${SP_DISTRO_VERSION:-}" == 26.10 ]] || return 0
            codename="${SP_DISTRO_CODENAME:-}"
            [[ "$codename" =~ ^[a-z][a-z0-9-]*$ ]] || sp_die 'Ubuntu release codename is missing or invalid; refusing to construct an APT source.'
            missing_archive_suites=''
            missing_security=0
            if ! sp_apt_sources_has_suite_component "$codename" universe; then missing_archive_suites="$codename"; fi
            if ! sp_apt_sources_has_suite_component "$codename-updates" universe; then
                missing_archive_suites="${missing_archive_suites:+$missing_archive_suites }$codename-updates"
            fi
            if ! sp_apt_sources_has_suite_component "$codename-security" universe; then missing_security=1; fi
            if [[ -n "$missing_archive_suites" || "$missing_security" == 1 ]]; then
                sp_confirm "Enable missing official Ubuntu Universe suites for $codename?" ||
                    sp_die 'Ubuntu Universe activation declined; no APT source was changed.'
                components=universe
                if ! sp_apt_sources_has_suite_component "$codename" main ||
                    ! sp_apt_sources_has_suite_component "$codename-updates" main ||
                    ! sp_apt_sources_has_suite_component "$codename-security" main; then
                    components='main universe'
                fi
                source_content=''
                if [[ -n "$missing_archive_suites" ]]; then
                    source_content="Types: deb
URIs: https://archive.ubuntu.com/ubuntu
Suites: $missing_archive_suites
Components: $components
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg"
                fi
                if (( missing_security )); then
                    [[ -z "$source_content" ]] || source_content+=$'\n\n'
                    source_content+="Types: deb
URIs: https://security.ubuntu.com/ubuntu
Suites: $codename-security
Components: $components
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg"
                fi
                sp_apt_managed_source_write "$SP_APT_SOURCES_DIR/sekaipop-universe.sources" "$source_content"
            else
                sp_info 'Ubuntu Universe is already configured for release, updates, and security suites.'
            fi
            ;;
    esac
}

sp_apt_bootstrap_rollback() {
    local index file expected_sha actual_sha
    for index in "${!SP_APT_BOOTSTRAP_CREATED[@]}"; do
        file="${SP_APT_BOOTSTRAP_CREATED[index]}"
        expected_sha="${SP_APT_BOOTSTRAP_CREATED_SHA[index]:-}"
        [[ -f "$file" && ! -L "$file" && -n "$expected_sha" ]] || continue
        actual_sha="$(sha256sum -- "$file" | awk '{print $1}')"
        if [[ "$actual_sha" == "$expected_sha" ]]; then
            sp_sudo rm -f -- "$file" || sp_warn "Could not roll back newly created APT source: $file"
        else
            sp_warn "Preserving APT source modified during installation; manual review required: $file"
        fi
    done
    SP_APT_BOOTSTRAP_CREATED=()
    SP_APT_BOOTSTRAP_CREATED_SHA=()
}
