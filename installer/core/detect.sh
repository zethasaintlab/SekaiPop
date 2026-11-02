#!/usr/bin/env bash

sp_detect_distribution() {
    local os_file=/etc/os-release
    if [[ "${SEKAIPOP_TEST_MODE:-0}" == 1 ]]; then
        [[ -n "${SEKAIPOP_TEST_OS_RELEASE:-}" && -f "$SEKAIPOP_TEST_OS_RELEASE" ]] || sp_die 'SEKAIPOP_TEST_MODE requires SEKAIPOP_TEST_OS_RELEASE.'
        os_file="$SEKAIPOP_TEST_OS_RELEASE"
    fi
    [[ -r "$os_file" ]] || sp_die "Cannot read $os_file."
    # /etc/os-release is trusted system metadata. The only override is the explicit test-only path above.
    # shellcheck disable=SC1090
    . "$os_file"

    SP_DISTRO_ID="${ID:-unknown}"
    SP_DISTRO_LIKE="${ID_LIKE:-}"
    SP_DISTRO_NAME="${PRETTY_NAME:-${NAME:-$SP_DISTRO_ID}}"
    SP_DISTRO_VERSION="${VERSION_ID:-unknown}"
    SP_DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    SP_DISTRO_VARIANT_ID="${VARIANT_ID:-}"
    SP_ARCH="$(uname -m)"
    SP_INIT=unknown
    if sp_have systemctl && [[ -d /run/systemd/system ]]; then SP_INIT=systemd; fi
    SP_DE="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"
    SP_SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
    SP_HYPRLAND_INSTALLED=0
    sp_have Hyprland && SP_HYPRLAND_INSTALLED=1
    SP_QS_INSTALLED=0
    sp_have qs && SP_QS_INSTALLED=1
    SP_QT_VERSION=''
    SP_HYPRLAND_VERSION=''

    if [[ "$SP_DISTRO_ID" == fedora ]]; then
        case "${SP_DISTRO_VARIANT_ID,,}" in
            silverblue|kinoite|sericea|onyx|sway-atomic|budgie-atomic)
                sp_die "Unsupported immutable Fedora variant '$SP_DISTRO_VARIANT_ID'; Fedora Atomic/ostree systems are excluded." ;;
        esac
        if [[ -e /run/ostree-booted ]]; then
            sp_die 'Unsupported Fedora Atomic/ostree system; this installer requires a mutable DNF-managed Fedora installation.'
        fi
    fi

    case "$SP_DISTRO_ID" in
        arch|endeavouros|cachyos) SP_BACKEND=arch; SP_PROFILE_ID=arch ;;
        kali) SP_BACKEND=apt; SP_PROFILE_ID=kali ;;
        fedora) SP_BACKEND=dnf5; SP_PROFILE_ID=fedora ;;
        debian) SP_BACKEND=apt; SP_PROFILE_ID=debian ;;
        ubuntu) SP_BACKEND=apt; SP_PROFILE_ID=ubuntu ;;
        *) sp_die "Unsupported distribution: $SP_DISTRO_NAME (ID=$SP_DISTRO_ID, ID_LIKE=${SP_DISTRO_LIKE:-unset}). ID_LIKE is informational only; no implicit backend fallback is permitted." 1 ;;
    esac

    [[ "$SP_ARCH" == x86_64 ]] || sp_die "Unsupported architecture '$SP_ARCH'; only x86_64 has been selected for the initial release." 1
    case "$SP_DISTRO_ID:$SP_DISTRO_VERSION:$SP_DISTRO_CODENAME" in
        fedora:44:*) SP_RELEASE_POLICY='Fedora 44; official Quickshell package verified; Hyprland must already be installed from a source the user trusts' ;;
        debian:13:trixie) SP_RELEASE_POLICY='Debian 13 (trixie); requires official trixie-backports enabled for Quickshell and Hyprland' ;;
        ubuntu:26.10:stonking) SP_RELEASE_POLICY='Ubuntu 26.10 (Stonking Stingray); official Universe package candidates' ;;
        arch:*:*) SP_RELEASE_POLICY='Arch Linux rolling; package and runtime version checks apply' ;;
        endeavouros:*:*) SP_RELEASE_POLICY='EndeavourOS rolling; package and runtime version checks apply' ;;
        cachyos:*:*) SP_RELEASE_POLICY='CachyOS rolling; package and runtime version checks apply' ;;
        kali:*:kali-rolling) SP_RELEASE_POLICY='Kali Linux kali-rolling; official Kali APT sources only; package candidates are suite-targeted' ;;
        *) sp_die "Unsupported or unverified release: $SP_DISTRO_NAME ($SP_DISTRO_VERSION ${SP_DISTRO_CODENAME:-}). Supported baselines: Fedora 44, Debian 13 trixie, Ubuntu 26.10 stonking, Kali kali-rolling, Arch Linux, EndeavourOS, and CachyOS rolling." 1 ;;
    esac

    sp_detect_package_manager
    export SP_DISTRO_ID SP_DISTRO_LIKE SP_DISTRO_NAME SP_DISTRO_VERSION SP_DISTRO_CODENAME SP_DISTRO_VARIANT_ID SP_ARCH SP_INIT SP_DE SP_SESSION_TYPE SP_BACKEND SP_PROFILE_ID SP_RELEASE_POLICY
}

sp_detect_package_manager() {
    case "$SP_BACKEND" in
        arch) sp_have pacman || sp_die 'Arch-family distribution detected but pacman is unavailable.' ;;
        dnf5)
            if sp_have dnf5; then SP_DNF_BIN=dnf5
            elif sp_have dnf; then
                local dnf_version
                dnf_version="$(dnf --version 2>/dev/null | head -n1 | grep -oE '[0-9]+' | head -n1 || true)"
                [[ "$dnf_version" == 5 ]] || sp_die 'Fedora backend requires DNF5; neither dnf5 nor a DNF5-compatible dnf command was found.'
                SP_DNF_BIN=dnf
            else sp_die 'DNF5 is unavailable.'; fi
            export SP_DNF_BIN
            ;;
        apt) sp_have apt-get && sp_have dpkg-query && sp_have apt-cache || sp_die 'APT backend requires apt-get, dpkg-query, and apt-cache.' ;;
        *) sp_die "Internal error: unsupported package backend '$SP_BACKEND'." ;;
    esac
}
