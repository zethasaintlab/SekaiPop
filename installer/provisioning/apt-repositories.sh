#!/usr/bin/env bash
# Provision only official distribution repositories required by supported APT profiles.
# This module never adds PPAs, third-party archives, mirrors, or package signing keys.

SP_APT_SOURCES_DIR="${SP_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
SP_APT_MAIN_SOURCES="${SP_APT_MAIN_SOURCES:-/etc/apt/sources.list}"
declare -ag SP_APT_BOOTSTRAP_CREATED=()

sp_apt_sources_contain() {
    local needle="$1" file
    shopt -s nullglob
    local -a files=("$SP_APT_SOURCES_DIR"/*.list "$SP_APT_SOURCES_DIR"/*.sources "$SP_APT_MAIN_SOURCES")
    shopt -u nullglob
    for file in "${files[@]}"; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        awk -v needle="$needle" '
            /^[[:space:]]*#/ { next }
            $1 == "Components:" || $1 == "Suites:" {
                for (i = 2; i <= NF; i++) if ($i == needle) found = 1
            }
            $1 == "deb" || $1 == "deb-src" {
                i = 2
                if ($i ~ /^\\[/) i++
                i += 2
                for (; i <= NF; i++) if ($i == needle) found = 1
            }
            END { exit !found }
        ' "$file" && return 0
    done
    return 1
}

sp_apt_managed_source_write() {
    local target="$1" content="$2" marker='# Managed by SekaiPop Universal Installer; official distribution archive only.'
    local tmp stage
    [[ "$target" == "$SP_APT_SOURCES_DIR/"* ]] || sp_die "Refusing APT source path outside the configured sources directory: $target"
    [[ ! -L "$target" ]] || sp_die "Refusing to replace symlinked APT source file: $target"
    if [[ -e "$target" ]]; then
        grep -Fq -- "$marker" "$target" && return 0
        sp_die "APT source target already exists and is not installer-managed: $target"
    fi
    tmp="$(mktemp)"
    printf '%s\n%s\n' "$marker" "$content" > "$tmp"
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
    SP_APT_BOOTSTRAP_CREATED+=("$target")
    sp_ok "Enabled official APT source: $target"
}

sp_apt_bootstrap_plan() {
    case "${SP_DISTRO_ID:-}" in
        debian)
            if [[ "${SP_DISTRO_VERSION:-}" == 13 ]] && ! sp_apt_sources_contain 'trixie-backports'; then
                sp_info 'Repository bootstrap required: official Debian trixie-backports (main).'
            fi
            ;;
        ubuntu)
            if [[ "${SP_DISTRO_VERSION:-}" == 26.10 ]] && ! sp_apt_sources_contain 'universe'; then
                sp_info "Repository bootstrap required: official Ubuntu Universe for ${SP_DISTRO_CODENAME:-stonking}."
            fi
            ;;
    esac
}

sp_apt_bootstrap_official_sources() {
    local codename
    SP_APT_BOOTSTRAP_CREATED=()
    [[ "${SP_BACKEND:-}" == apt ]] || return 0
    case "${SP_DISTRO_ID:-}" in
        debian)
            [[ "${SP_DISTRO_VERSION:-}" == 13 && "${SP_DISTRO_CODENAME:-}" == trixie ]] || return 0
            if ! sp_apt_sources_contain 'trixie-backports'; then
                sp_confirm 'Enable the official Debian 13 trixie-backports repository? This adds only the signed Debian archive source.' ||
                    sp_die 'Debian backports activation declined; no APT source was changed.'
                sp_apt_managed_source_write "$SP_APT_SOURCES_DIR/sekaipop-trixie-backports.sources" \
                    'Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg'
            else
                sp_info 'Official Debian trixie-backports is already configured.'
            fi
            ;;
        ubuntu)
            [[ "${SP_DISTRO_VERSION:-}" == 26.10 ]] || return 0
            codename="${SP_DISTRO_CODENAME:-}"
            [[ "$codename" =~ ^[a-z][a-z0-9-]*$ ]] || sp_die 'Ubuntu release codename is missing or invalid; refusing to construct an APT source.'
            if ! sp_apt_sources_contain 'universe'; then
                sp_confirm "Enable the official Ubuntu Universe component for $codename?" ||
                    sp_die 'Ubuntu Universe activation declined; no APT source was changed.'
                sp_apt_managed_source_write "$SP_APT_SOURCES_DIR/sekaipop-universe.sources" \
                    "Types: deb
URIs: https://archive.ubuntu.com/ubuntu
Suites: $codename $codename-updates
Components: universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: https://security.ubuntu.com/ubuntu
Suites: $codename-security
Components: universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg"
            else
                sp_info 'Ubuntu Universe is already configured.'
            fi
            ;;
    esac
}

sp_apt_bootstrap_rollback() {
    local file
    for file in "${SP_APT_BOOTSTRAP_CREATED[@]}"; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        if grep -Fq '# Managed by SekaiPop Universal Installer; official distribution archive only.' "$file"; then
            sp_sudo rm -f -- "$file" || sp_warn "Could not roll back newly created APT source: $file"
        fi
    done
    SP_APT_BOOTSTRAP_CREATED=()
}
