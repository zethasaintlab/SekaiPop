#!/usr/bin/env bash

sp_qt_shadertools_required() {
    local qt_version package_spec resolved
    local -a qt_packages=()

    # The checked-in .qsb files are built with Qt 6.12. Rebuilding is only needed
    # when the effective installed/candidate Qt runtime is older than that.
    qt_version="$(sp_qt_version || true)"
    if [[ -z "$qt_version" ]]; then
        read -r -a qt_packages <<< "${DISTRO_PACKAGE_MAP[qt6-base]-}"
        for package_spec in "${qt_packages[@]}"; do
            resolved="$(sp_resolve_package_spec "$package_spec" || true)"
            [[ -n "$resolved" ]] || continue
            qt_version="$(pm_get_package_version "$resolved" 2>/dev/null || true)"
            [[ -n "$qt_version" ]] && break
        done
    fi

    [[ -n "$qt_version" ]] || return 2
    ! sp_version_ge "$qt_version" 6.12.0
}

sp_load_distro_profile() {
    source "$SP_ROOT/installer/distros/$SP_PROFILE_ID/packages.sh"
    SP_PROFILE_REQS=("${SP_REQ_CORE[@]}")
    if [[ "$SP_PROFILE" == standard || "$SP_PROFILE" == full ]]; then
        SP_PROFILE_REQS+=("${SP_REQ_STANDARD[@]}")
        (( SP_NO_DESKTOP )) || SP_PROFILE_REQS+=("${SP_REQ_DESKTOP[@]}")
    fi
    if [[ "$SP_PROFILE" == full ]]; then SP_PROFILE_REQS+=("${SP_REQ_FULL[@]}"); fi
    SP_QT_SHADER_REQUIREMENT_UNKNOWN=0
    if sp_qt_shadertools_required; then
        SP_PROFILE_REQS+=(qt6-shadertools)
    else
        local qt_requirement_status=$?
        if (( qt_requirement_status == 2 )); then
            SP_QT_SHADER_REQUIREMENT_UNKNOWN=1
        fi
    fi
    return 0
}

sp_fedora_power_profile_api_available() {
    local owner interfaces
    [[ "${SP_DISTRO_ID:-}" == fedora ]] || return 1
    sp_have busctl || return 1

    owner="$(busctl --system call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameHasOwner s org.freedesktop.UPower.PowerProfiles 2>/dev/null)" || return 1
    [[ "$owner" == 'b true' ]] || return 1

    interfaces="$(busctl --system --no-pager introspect org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles 2>/dev/null)" || return 1
    [[ "$interfaces" == *'org.freedesktop.UPower.PowerProfiles'* ]]
}

sp_fedora_tuned_ppd_installed() {
    [[ "${SP_DISTRO_ID:-}" == fedora ]] || return 1
    sp_have rpm && rpm -q tuned-ppd >/dev/null 2>&1
}

sp_fedora_tlp_pd_installed() {
    [[ "${SP_DISTRO_ID:-}" == fedora ]] || return 1
    sp_have rpm && rpm -q tlp-pd >/dev/null 2>&1
}

sp_fedora_tlp_installed() {
    [[ "${SP_DISTRO_ID:-}" == fedora ]] || return 1
    sp_have rpm && rpm -q tlp >/dev/null 2>&1
}

sp_fedora_power_profile_provider_installed() {
    [[ "${SP_DISTRO_ID:-}" == fedora ]] || return 1
    sp_have rpm || return 1
    rpm -q tuned-ppd >/dev/null 2>&1 ||
        rpm -q tlp-pd >/dev/null 2>&1 ||
        rpm -q power-profiles-daemon >/dev/null 2>&1
}

sp_fedora_power_profile_provider_count() {
    [[ "${SP_DISTRO_ID:-}" == fedora ]] || return 1
    sp_have rpm || return 1
    local count=0
    rpm -q tuned-ppd >/dev/null 2>&1 && ((count += 1))
    rpm -q tlp-pd >/dev/null 2>&1 && ((count += 1))
    rpm -q power-profiles-daemon >/dev/null 2>&1 && ((count += 1))
    printf '%s\n' "$count"
}

sp_runtime_requirement_present() {
    local req="$1" version
    case "$req" in
        quickshell) sp_have qs ;;
        ffmpeg) sp_have ffmpeg ;;
        hyprland)
            version="$(sp_hyprland_version 2>/dev/null || true)"
            [[ -n "$version" ]] && sp_version_ge "$version" 0.55.0
            ;;
        python-numpy) sp_have python3 && python3 -c 'import numpy' >/dev/null 2>&1 ;;
        python-aubio) sp_have python3 && python3 -c 'import aubio' >/dev/null 2>&1 ;;
        matugen)
            if sp_have matugen; then
                version="$(matugen --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true)"
                [[ -n "$version" ]] && sp_version_ge "$version" 2.0.0
            else return 1; fi
            ;;
        songrec) sp_have songrec ;;
        mpvpaper) sp_have mpvpaper ;;
        nwg-displays) sp_have nwg-displays ;;
        hypridle) sp_have hypridle ;;
        nodejs) sp_have node ;;
        pnpm) sp_have pnpm ;;
        power-profiles-daemon)
            if [[ "${SP_DISTRO_ID:-}" == fedora ]]; then
                sp_fedora_power_profile_api_available
            else
                sp_have powerprofilesctl
            fi
            ;;
        material-symbols) sp_have fc-match && fc-match -f '%{family}\n' 'Material Symbols Rounded' 2>/dev/null | grep -qi 'Material Symbols' ;;
        google-sans-flex) sp_have fc-match && fc-match -f '%{family}\n' 'Google Sans Flex' 2>/dev/null | grep -qi 'Google Sans Flex' ;;
        graphics-egl)
            if sp_have ldconfig; then ldconfig -p 2>/dev/null | grep -q 'libEGL\.so';
            else [[ -e /usr/lib/libEGL.so.1 || -e /usr/lib64/libEGL.so.1 || -e /usr/lib/x86_64-linux-gnu/libEGL.so.1 ]]; fi
            ;;
        portal-hyprland) [[ -x /usr/libexec/xdg-desktop-portal-hyprland || -x /usr/lib/xdg-desktop-portal-hyprland || -x /usr/lib64/xdg-desktop-portal-hyprland ]] ;;
        portal-gtk) [[ -x /usr/libexec/xdg-desktop-portal-gtk || -x /usr/lib/xdg-desktop-portal-gtk || -x /usr/lib64/xdg-desktop-portal-gtk ]] ;;
        *) return 1 ;;
    esac
}

sp_build_package_plan() {
    local req class package_text package_spec resolved minimum version
    local -A seen_packages=() seen_requirements=()
    SP_INSTALL_PKGS=() SP_INSTALL_CORE=() SP_INSTALL_OPTIONAL=()
    SP_MISSING_CORE=() SP_MISSING_OPTIONAL=() SP_ALREADY_INSTALLED=()
    SP_RUNTIME_SATISFIED=() SP_PROVIDER_INSTALLED=()

    for req in "${SP_PROFILE_REQS[@]}"; do
        [[ -n "$req" ]] || continue
        [[ -z "${seen_requirements[$req]:-}" ]] || continue
        seen_requirements[$req]=1
        if [[ " ${SP_REQ_CORE[*]} " == *" $req "* || "$req" == qt6-shadertools ]]; then
            class=core
        else
            class=optional
        fi
        # A compatible capability already present on the host wins over package-name
        # mapping. This avoids installing a second provider merely because its package
        # name differs from this profile's preferred native package.
        if [[ "$req" == power-profiles-daemon && "$SP_DISTRO_ID" == fedora ]] &&
            sp_fedora_tlp_installed &&
            ! sp_fedora_tlp_pd_installed &&
            ! sp_fedora_tuned_ppd_installed &&
            ! { sp_have rpm && rpm -q power-profiles-daemon >/dev/null 2>&1; }; then
            SP_MISSING_OPTIONAL+=("$req (TLP is installed without tlp-pd; provider installation was skipped to avoid a TLP/PPD conflict)")
            continue
        fi
        if sp_runtime_requirement_present "$req"; then
            SP_RUNTIME_SATISFIED+=("$req")
            continue
        fi
        if [[ "$req" == power-profiles-daemon && "${SP_DISTRO_ID:-}" == fedora ]] &&
            sp_fedora_power_profile_provider_installed; then
            SP_PROVIDER_INSTALLED+=("$req (an existing Fedora provider package is installed; service activation will be offered)")
            continue
        fi
        package_text="${DISTRO_PACKAGE_MAP[$req]-}"

        if [[ -z "$package_text" ]]; then
            if [[ "$class" == core ]]; then
                SP_MISSING_CORE+=("$req (no approved native package mapping; $(sp_describe_requirement "$req"))")
            else
                SP_MISSING_OPTIONAL+=("$req (no native package mapping)")
            fi
            continue
        fi

        local -a package_specs=()
        read -r -a package_specs <<< "$package_text"
        for package_spec in "${package_specs[@]}"; do
            resolved="$(sp_resolve_package_spec "$package_spec" || true)"
            if [[ -z "$resolved" ]]; then
                if [[ "$class" == core ]]; then SP_MISSING_CORE+=("$req: $package_spec")
                else SP_MISSING_OPTIONAL+=("$req: $package_spec"); fi
                continue
            fi
            minimum="${SP_REQ_MIN_VERSION[$req]:-}"
            if [[ -n "$minimum" ]]; then
                version="$(pm_get_package_version "$resolved" 2>/dev/null || true)"
                if [[ -z "$version" ]] || ! sp_version_ge "$version" "$minimum"; then
                    local version_problem="$req: $resolved candidate/installed version ${version:-unknown} (requires >= $minimum)"
                    if [[ "$class" == core ]]; then SP_MISSING_CORE+=("$version_problem")
                    else SP_MISSING_OPTIONAL+=("$version_problem"); fi
                    continue
                fi
            fi
            if pm_query_installed "$resolved"; then
                SP_ALREADY_INSTALLED+=("$resolved")
            elif [[ -z "${seen_packages[$resolved]:-}" ]]; then
                seen_packages[$resolved]=1
                SP_INSTALL_PKGS+=("$resolved")
                if [[ "$class" == core ]]; then SP_INSTALL_CORE+=("$resolved"); else SP_INSTALL_OPTIONAL+=("$resolved"); fi
            fi
        done
    done
    if (( ${SP_QT_SHADER_REQUIREMENT_UNKNOWN:-0} )); then
        SP_MISSING_CORE+=("qt6-shadertools: effective Qt version is unknown; refresh package metadata or rerun without --no-update before installation")
    fi
}

sp_print_package_plan() {
    printf '\nSekaiPop dependency plan\n'
    printf '  Distribution : %s (%s %s)\n' "$SP_DISTRO_NAME" "$SP_DISTRO_ID" "$SP_DISTRO_VERSION"
    printf '  Release gate : %s\n' "$SP_RELEASE_POLICY"
    printf '  Backend      : %s\n' "$SP_BACKEND"
    printf '  Architecture : %s\n' "$SP_ARCH"
    printf '  Init system  : %s\n' "$SP_INIT"
    printf '  Profile      : %s\n' "$SP_PROFILE"
    printf '  Hyprland     : %s\n' "$SP_HYPR"
    if [[ "$SP_DISTRO_ID" == debian ]]; then
        printf '  APT pinning  : Quickshell and Hyprland target trixie-backports individually; other packages use normal APT priorities.\n'
    fi
    printf '\nAlready installed (%d):\n' "${#SP_ALREADY_INSTALLED[@]}"
    printf '  %s\n' "${SP_ALREADY_INSTALLED[@]:-none}"
    printf '\nRuntime-provided (%d):\n' "${#SP_RUNTIME_SATISFIED[@]}"
    printf '  %s\n' "${SP_RUNTIME_SATISFIED[@]:-none}"
    if (("${#SP_PROVIDER_INSTALLED[@]}")); then
        printf '\nExisting provider packages (%d; activation may be offered):\n' "${#SP_PROVIDER_INSTALLED[@]}"
        printf '  %s\n' "${SP_PROVIDER_INSTALLED[@]}"
    fi
    printf '\nTo install (%d):\n' "${#SP_INSTALL_PKGS[@]}"
    printf '  %s\n' "${SP_INSTALL_PKGS[@]:-none}"
    if (("${#SP_MISSING_CORE[@]}")); then
        printf '\nUnavailable mandatory requirements (%d):\n' "${#SP_MISSING_CORE[@]}"
        printf '  %s\n' "${SP_MISSING_CORE[@]}"
    fi
    if (("${#SP_MISSING_OPTIONAL[@]}")); then
        printf '\nUnavailable optional requirements (%d; those features remain disabled):\n' "${#SP_MISSING_OPTIONAL[@]}"
        printf '  %s\n' "${SP_MISSING_OPTIONAL[@]}"
    fi
    printf '\nRepository policy: configured native distribution repositories only. No AUR, COPR, PPA, third-party RPM/DEB, or source build is enabled by this installer.\n'
    if [[ "$SP_BACKEND" == arch ]] && (("${#SP_INSTALL_PKGS[@]}")); then
        if (( SP_SYSTEM_UPGRADE )); then printf 'Arch transaction: pacman -Syu --needed (explicitly authorized by --system-upgrade).\n'
        else printf 'Arch transaction: pacman -S --needed against the existing sync DB; no isolated -Sy.\n'; fi
    fi
    if [[ "$SP_DISTRO_ID" == fedora ]]; then
        printf 'Fedora note: Hyprland is not available from Fedora 44 official repositories in this verified baseline; an existing compatible Hyprland is required.\n'
    fi
    printf '\n'
}
