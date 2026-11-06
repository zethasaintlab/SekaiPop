#!/usr/bin/env bash
# Fedora RPM provider for Hyprland and xdg-desktop-portal-hyprland.

SP_FEDORA_COPR_PROVIDER_REPO_ID="sekaipop-copr-lionheartp-hyprland"
SP_FEDORA_COPR_PROVIDER_KEY_FINGERPRINT="97E23476C89635135407C7D5E9BA41342C4B2995"
SP_FEDORA_COPR_PROVIDER_KEY_URL="https://download.copr.fedorainfracloud.org/results/lionheartp/Hyprland/pubkey.gpg"
SP_FEDORA_COPR_PROVIDER_REQUIRED=0
SP_FEDORA_COPR_PROVIDER_SESSION_CREATED_BY_TRANSACTION=0
SP_FEDORA_COPR_PROVIDER_PACKAGES=()

sp_fedora_copr_provider_supported() {
    [[ "${SP_DISTRO_ID:-}" == fedora ]] || return 1
    [[ "${SP_DISTRO_VERSION:-}" == 44 || "${SP_DISTRO_VERSION:-}" == 45 ]] || return 1
    [[ "${SP_ARCH:-}" == x86_64 && "${SP_INIT:-}" == systemd ]] || return 1
    [[ ! -e "${SP_OSTREE_BOOTED_MARKER:-/run/ostree-booted}" ]]
}

sp_fedora_copr_provider_nevra() {
    local release="${SP_DISTRO_VERSION:-}"
    case "$release" in
        44)
            case "$1" in
                hyprland) printf '%s\n' 'hyprland-0.57.1-1.fc44.x86_64' ;;
                portal) printf '%s\n' 'xdg-desktop-portal-hyprland-1:1.5.0-1.fc44.x86_64' ;;
                *) return 2 ;;
            esac
            ;;
        45)
            case "$1" in
                hyprland) printf '%s\n' 'hyprland-0.57.1-1.fc45.x86_64' ;;
                portal) printf '%s\n' 'xdg-desktop-portal-hyprland-1:1.5.0-1.fc45.x86_64' ;;
                *) return 2 ;;
            esac
            ;;
        *) return 2 ;;
    esac
}

sp_fedora_copr_provider_package_versions_match() {
    local hyprland_expected portal_expected hyprland_actual portal_actual
    hyprland_expected="$(sp_fedora_copr_provider_nevra hyprland)" || return 1
    portal_expected="$(sp_fedora_copr_provider_nevra portal)" || return 1
    hyprland_actual="$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' hyprland 2>/dev/null)" || return 1
    portal_actual="$(rpm -q --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}' xdg-desktop-portal-hyprland 2>/dev/null)" || return 1
    [[ "$hyprland_actual" == "$hyprland_expected" ]] || return 1
    [[ "$portal_actual" == "$portal_expected" ]] || return 1
    local expected_key_id="${SP_FEDORA_COPR_PROVIDER_KEY_FINGERPRINT: -16}"
    local hyprland_signature portal_signature
    hyprland_signature="$(rpm -q --qf '%{SIGPGP:pgpsig}' hyprland 2>/dev/null)" || return 1
    portal_signature="$(rpm -q --qf '%{SIGPGP:pgpsig}' xdg-desktop-portal-hyprland 2>/dev/null)" || return 1
    grep -Eiq "Key ID $expected_key_id" <<< "$hyprland_signature" || return 1
    grep -Eiq "Key ID $expected_key_id" <<< "$portal_signature" || return 1
    return 0
}

sp_fedora_copr_provider_ready() {
    sp_fedora_copr_provider_package_versions_match || return 1
    [[ -x /usr/bin/Hyprland && -x /usr/bin/start-hyprland ]] || return 1
    [[ -f /usr/lib/systemd/user/hyprland-session.target ]] || return 1
    [[ -x /usr/libexec/xdg-desktop-portal-hyprland ]] || return 1
    [[ -f /usr/lib/systemd/user/xdg-desktop-portal-hyprland.service ]] || return 1
    [[ -f /usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service ]] || return 1
    [[ -f /usr/share/xdg-desktop-portal/portals/hyprland.portal ]] || return 1
    [[ -f /var/lib/sekaipop/fedora-hyprland-copr/ownership.json ]] || return 1
    [[ -f /etc/pki/rpm-gpg/RPM-GPG-KEY-sekaipop-lionheartp-hyprland ]] || return 1
    local session="/usr/share/wayland-sessions/sekaipop-hyprland.desktop"
    [[ -f "$session" && ! -L "$session" ]] || return 1
    grep -Fxq 'Exec=/usr/bin/start-hyprland' "$session" || return 1
    grep -Fxq 'TryExec=/usr/bin/start-hyprland' "$session" || return 1
    return 0
}

sp_fedora_copr_provider_add_system_package() {
    local logical="$1" executable="$2" package_text resolved package found
    sp_have "$executable" && return 0
    package_text="${DISTRO_PACKAGE_MAP[$logical]-}"
    if [[ -z "$package_text" ]]; then
        SP_MISSING_CORE+=("$logical (required by the Fedora Hyprland COPR provider)")
        return 1
    fi
    resolved="$(sp_resolve_package_spec "$package_text" 2>/dev/null || true)"
    if [[ -z "$resolved" ]]; then
        SP_MISSING_CORE+=("$logical (required by the Fedora Hyprland COPR provider; no trusted Fedora package candidate)")
        return 1
    fi
    read -r -a packages <<< "$resolved"
    for package in "${packages[@]}"; do
        if pm_query_installed "$package"; then
            continue
        fi
        found=0
        local existing
        for existing in "${SP_INSTALL_PKGS[@]}"; do
            if [[ "$existing" == "$package" ]]; then found=1; break; fi
        done
        if (( ! found )); then
            SP_INSTALL_PKGS+=("$package")
            SP_INSTALL_CORE+=("$package")
        fi
    done
}

sp_fedora_copr_provider_plan() {
    sp_fedora_copr_provider_supported || return 1
    SP_FEDORA_COPR_PROVIDER_REQUIRED=1
    SP_FEDORA_HOST_PROVIDER_REQUIRED=1
    SP_FEDORA_HOST_PROVIDER_STRATEGY=copr
    SP_FEDORA_COPR_PROVIDER_PACKAGES=()
    if ! sp_fedora_copr_provider_package_versions_match; then
        SP_FEDORA_COPR_PROVIDER_PACKAGES+=("$(sp_fedora_copr_provider_nevra hyprland)")
        SP_FEDORA_COPR_PROVIDER_PACKAGES+=("$(sp_fedora_copr_provider_nevra portal)")
    fi
    sp_fedora_copr_provider_add_system_package python3 python3
    sp_fedora_copr_provider_add_system_package curl curl
    sp_fedora_copr_provider_add_system_package gnupg2 gpg
}

sp_fedora_copr_provider_check_official_packages() {
    local candidate
    candidate="$("$SP_DNF_BIN" --repo=fedora,updates repoquery --available --qf '%{version}' hyprland 2>/dev/null | sort -Vu | tail -n1 || true)"
    if [[ -n "$candidate" ]] && [[ "$(printf '%s\n%s\n' 0.55.0 "$candidate" | sort -V | tail -n1)" == "$candidate" ]]; then
        sp_die "A compatible Hyprland package is now available in official Fedora repositories ($candidate). The pinned provider policy must be reviewed before using a COPR."
    fi
}

sp_fedora_copr_provider_install() {
    sp_fedora_copr_provider_supported || sp_die "the pinned COPR provider supports only Fedora 44/45 x86_64 systemd hosts"
    (
        set -Eeuo pipefail
        local keyfile actual expected_hyprland expected_portal available_hyprland available_portal
        keyfile="$(mktemp "${TMPDIR:-/tmp}/sekaipop-copr-key.XXXXXX")"
        chmod 600 "$keyfile"
        trap 'rm -f -- "$keyfile"' EXIT

        sp_info "Downloading the pinned lionheartp/Hyprland COPR signing key"
        curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
            --output "$keyfile" "$SP_FEDORA_COPR_PROVIDER_KEY_URL"
        actual="$(gpg --batch --no-options --with-colons --show-keys "$keyfile" 2>/dev/null | awk -F: '$1 == "fpr" { print toupper($10); exit }')"
        if [[ "$actual" != "$SP_FEDORA_COPR_PROVIDER_KEY_FINGERPRINT" ]]; then
            sp_die "COPR signing-key fingerprint mismatch; expected $SP_FEDORA_COPR_PROVIDER_KEY_FINGERPRINT, received ${actual:-<none>}"
        fi

        sp_info "Installing the verified COPR repository and signing key"
        sp_sudo python3 "$SP_ROOT/tools/fedora-hyprland-copr-provider.py" install-repo --key-file "$keyfile"

        sp_info "Refreshing only the selected COPR and official Fedora repositories"
        sp_sudo "$SP_DNF_BIN" --repo="$SP_FEDORA_COPR_PROVIDER_REPO_ID,fedora,updates" makecache --refresh

        sp_fedora_copr_provider_check_official_packages
        expected_hyprland="$(sp_fedora_copr_provider_nevra hyprland)"
        expected_portal="$(sp_fedora_copr_provider_nevra portal)"
        available_hyprland="$("$SP_DNF_BIN" --repo="$SP_FEDORA_COPR_PROVIDER_REPO_ID" repoquery --available --qf '%{name}-%{version}-%{release}.%{arch}' hyprland | sort -Vu | tail -n1)"
        available_portal="$("$SP_DNF_BIN" --repo="$SP_FEDORA_COPR_PROVIDER_REPO_ID" repoquery --available --qf '%{name}-%{epoch}:%{version}-%{release}.%{arch}' xdg-desktop-portal-hyprland | sort -Vu | tail -n1)"
        if [[ "$available_hyprland" != "$expected_hyprland" ]]; then
            sp_die "COPR Hyprland candidate mismatch: expected $expected_hyprland, received ${available_hyprland:-<none>}"
        fi
        if [[ "$available_portal" != "$expected_portal" ]]; then
            sp_die "COPR portal candidate mismatch: expected $expected_portal, received ${available_portal:-<none>}"
        fi

        if ! sp_fedora_copr_provider_package_versions_match; then
            sp_info "Installing pinned Hyprland and portal RPMs from the verified COPR"
            sp_sudo "$SP_DNF_BIN" --repo="$SP_FEDORA_COPR_PROVIDER_REPO_ID,fedora,updates" install \
                --assumeyes --setopt=install_weak_deps=False --from-repo="$SP_FEDORA_COPR_PROVIDER_REPO_ID" \
                "$expected_hyprland" "$expected_portal"
        fi

        local session="/usr/share/wayland-sessions/sekaipop-hyprland.desktop"
        local session_preexisting=0
        [[ -f "$session" ]] && session_preexisting=1
        sp_info "Validating RPM signatures, package ownership, systemd units and portal integration"
        sp_sudo python3 "$SP_ROOT/tools/fedora-hyprland-copr-provider.py" register-session
        if (( ! session_preexisting )); then
            SP_FEDORA_COPR_PROVIDER_SESSION_CREATED_BY_TRANSACTION=1
        fi
        if systemctl --user show-environment >/dev/null 2>&1; then
            systemctl --user daemon-reload || sp_warn "systemd user-manager reload failed; the next login will discover the installed units"
        fi
        sp_ok "Fedora Hyprland provider installed and verified (Hyprland 0.57.1, portal 1.5.0)"
    )
}

sp_fedora_copr_provider_rollback() {
    (( SP_FEDORA_COPR_PROVIDER_SESSION_CREATED_BY_TRANSACTION )) || return 0
    if sp_sudo python3 "$SP_ROOT/tools/fedora-hyprland-copr-provider.py" unregister-session; then
        SP_FEDORA_COPR_PROVIDER_SESSION_CREATED_BY_TRANSACTION=0
        sp_warn "Removed the SekaiPop login-session entry after a failed desktop deployment; verified RPMs and the update repository remain installed"
    else
        sp_warn "Could not safely unregister the SekaiPop session; the RPM provider remains installed for recovery"
    fi
}

sp_fedora_copr_provider_commit() {
    SP_FEDORA_COPR_PROVIDER_SESSION_CREATED_BY_TRANSACTION=0
}
