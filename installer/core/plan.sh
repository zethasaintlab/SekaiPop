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

    [[ -n "$qt_version" ]] || return 1
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
    if sp_qt_shadertools_required; then
        SP_PROFILE_REQS+=(qt6-shadertools)
    fi
    return 0
}

sp_kali_apt_sources_are_safe() {
    local apt_root=/etc/apt file uri host suite found=0 invalid=0
    local -a source_files=()

    if [[ "${SEKAIPOP_TEST_MODE:-0}" == 1 && -n "${SEKAIPOP_TEST_APT_ROOT:-}" ]]; then
        apt_root="$SEKAIPOP_TEST_APT_ROOT"
    fi

    sp_have apt-config || return 1
    local apt_config root_dir
    apt_config="$(apt-config dump 2>/dev/null)" || return 1
    grep -Fqx 'Dir::Etc "etc/apt";' <<< "$apt_config" || return 1
    grep -Fqx 'Dir::Etc::sourcelist "sources.list";' <<< "$apt_config" || return 1
    grep -Fqx 'Dir::Etc::sourceparts "sources.list.d";' <<< "$apt_config" || return 1
    root_dir="$(awk '$1 == "Dir::RootDir" { gsub(/[";]/, "", $2); print $2; exit }' <<< "$apt_config")"
    [[ -z "$root_dir" || "$root_dir" == / ]] || return 1

    source_files=("$apt_root/sources.list")
    for file in "$apt_root"/sources.list.d/*.list "$apt_root"/sources.list.d/*.sources; do
        [[ -f "$file" ]] && source_files+=("$file")
    done

    for file in "${source_files[@]}"; do
        [[ -f "$file" && -r "$file" ]] || continue
        case "$file" in
            *.sources)
                while IFS='|' read -r uris suites; do
                    [[ -n "$uris" && -n "$suites" ]] || continue
                    found=1
                    for uri in $uris; do
                        host="${uri#*://}"
                        host="${host%%/*}"
                        host="${host%%:*}"
                        case "$host" in
                            http.kali.org|archive.kali.org) ;;
                            *) invalid=1 ;;
                        esac
                    done
                    for suite in $suites; do
                        [[ "$suite" == kali-rolling ]] || invalid=1
                    done
                done < <(awk '
                    function emit() {
                        if (types ~ /(^|[[:space:]])deb([[:space:]]|$)/ && enabled != "no" && uris != "" && suites != "") {
                            print uris "|" suites
                        }
                        types = uris = suites = ""
                        enabled = "yes"
                        last = ""
                    }
                    /^[[:space:]]*#/ { next }
                    /^[[:space:]]*$/ { emit(); next }
                    /^[[:space:]]*Types:[[:space:]]*/ {
                        value = $0; sub(/^[[:space:]]*Types:[[:space:]]*/, "", value)
                        types = value; last = "Types"; next
                    }
                    /^[[:space:]]*URIs:[[:space:]]*/ {
                        value = $0; sub(/^[[:space:]]*URIs:[[:space:]]*/, "", value)
                        uris = value; last = "URIs"; next
                    }
                    /^[[:space:]]*Suites:[[:space:]]*/ {
                        value = $0; sub(/^[[:space:]]*Suites:[[:space:]]*/, "", value)
                        suites = value; last = "Suites"; next
                    }
                    /^[[:space:]]*Enabled:[[:space:]]*/ {
                        value = $0; sub(/^[[:space:]]*Enabled:[[:space:]]*/, "", value)
                        enabled = value; last = "Enabled"; next
                    }
                    /^[^[:space:]]/ { last = ""; next }
                    /^[[:space:]]+/ {
                        value = $0; sub(/^[[:space:]]+/, "", value)
                        if (last == "URIs") uris = uris " " value
                        else if (last == "Suites") suites = suites " " value
                        else if (last == "Types") types = types " " value
                        next
                    }
                    END { emit() }
                ' "$file")
                ;;
            *)
                while IFS='|' read -r uri suite; do
                    [[ -n "$uri" && -n "$suite" ]] || continue
                    found=1
                    host="${uri#*://}"
                    host="${host%%/*}"
                    host="${host%%:*}"
                    case "$host" in
                        http.kali.org|archive.kali.org) ;;
                        *) invalid=1 ;;
                    esac
                    [[ "$suite" == kali-rolling ]] || invalid=1
                done < <(awk '
                    {
                        sub(/^[[:space:]]+/, "", $0)
                        if ($0 ~ /^#/ || $1 != "deb") next
                        count = split($0, fields, /[[:space:]]+/)
                        field_index = 2
                        if (fields[field_index] ~ /^\[/) {
                            while (field_index <= count && fields[field_index] !~ /\]$/) field_index++
                            field_index++
                        }
                        if (field_index + 1 <= count) print fields[field_index] "|" fields[field_index + 1]
                    }
                ' "$file")
                ;;
        esac
    done

    (( found > 0 && invalid == 0 ))
}

sp_fedora_tuned_ppd_available() {
    local owner interfaces
    [[ "${SP_DISTRO_ID:-}" == fedora ]] || return 1
    sp_have rpm && rpm -q tuned-ppd >/dev/null 2>&1 || return 1
    sp_have systemctl && systemctl is-active --quiet tuned-ppd.service || return 1
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

sp_fedora_power_profile_provider_installed() {
    [[ "${SP_DISTRO_ID:-}" == fedora ]] || return 1
    sp_have rpm || return 1
    rpm -q tuned-ppd >/dev/null 2>&1 ||
        rpm -q tlp-pd >/dev/null 2>&1 ||
        rpm -q power-profiles-daemon >/dev/null 2>&1 ||
        rpm -q tlp >/dev/null 2>&1
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
            if sp_have powerprofilesctl; then return 0; fi
            sp_fedora_tuned_ppd_available || sp_fedora_power_profile_provider_installed
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
    SP_RUNTIME_SATISFIED=()

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
        if sp_runtime_requirement_present "$req"; then
            SP_RUNTIME_SATISFIED+=("$req")
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
