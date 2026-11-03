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
    local apt_root=/etc/apt file uri suite found=0 invalid=0
    local -a source_files=()

    if [[ "${SEKAIPOP_TEST_MODE:-0}" == 1 && -n "${SEKAIPOP_TEST_APT_ROOT:-}" ]]; then
        apt_root="$SEKAIPOP_TEST_APT_ROOT"
    fi

    [[ -z "${APT_CONFIG:-}" ]] || return 1
    if [[ "${SEKAIPOP_TEST_MODE:-0}" != 1 ]] &&
        [[ ! -r /usr/share/keyrings/kali-archive-keyring.gpg ]]; then
        return 1
    fi
    sp_have apt-config || return 1
    local apt_config root_dir
    apt_config="$(apt-config dump 2>/dev/null)" || return 1
    grep -Fqx 'Dir "/";' <<< "$apt_config" || return 1
    grep -Fqx 'Dir::Etc "etc/apt";' <<< "$apt_config" || return 1
    grep -Fqx 'Dir::Etc::sourcelist "sources.list";' <<< "$apt_config" || return 1
    grep -Fqx 'Dir::Etc::sourceparts "sources.list.d";' <<< "$apt_config" || return 1
    if grep -Eiq '^(Acquire::AllowInsecureRepositories|Acquire::AllowDowngradeToInsecureRepositories|APT::Get::AllowUnauthenticated)[[:space:]]+"?(true|yes|1)' <<< "$apt_config"; then
        return 1
    fi
    root_dir="$(awk '$1 == "Dir::RootDir" { gsub(/[";]/, "", $2); print $2; exit }' <<< "$apt_config")"
    [[ -z "$root_dir" || "$root_dir" == / ]] || return 1

    source_files=()
    if [[ -e "$apt_root/sources.list" || -L "$apt_root/sources.list" ]]; then
        if [[ -f "$apt_root/sources.list" && -r "$apt_root/sources.list" ]]; then
            source_files+=("$apt_root/sources.list")
        else
            invalid=1
        fi
    fi
    if [[ -e "$apt_root/sources.list.d" || -L "$apt_root/sources.list.d" ]]; then
        [[ -d "$apt_root/sources.list.d" && -r "$apt_root/sources.list.d" ]] || invalid=1
    fi
    for file in "$apt_root"/sources.list.d/*.list "$apt_root"/sources.list.d/*.sources; do
        [[ -e "$file" || -L "$file" ]] || continue
        if [[ -f "$file" && -r "$file" ]]; then
            source_files+=("$file")
        else
            invalid=1
        fi
    done

    for file in "${source_files[@]}"; do
        case "$file" in
            *.sources)
                while IFS='|' read -r uris suites signed_by trusted allow_insecure binary; do
                    [[ -n "$uris" && -n "$suites" && "$binary" =~ ^[01]$ ]] || { invalid=1; continue; }
                    [[ "$binary" == 1 ]] && found=1
                    [[ "$signed_by" == /usr/share/keyrings/kali-archive-keyring.gpg ]] || invalid=1
                    [[ -z "$trusted" || "$trusted" == no ]] || invalid=1
                    [[ -z "$allow_insecure" || "$allow_insecure" == no ]] || invalid=1
                    for uri in $uris; do
                        case "$uri" in
                            http://http.kali.org/kali|http://http.kali.org/kali/) ;;
                            *) invalid=1 ;;
                        esac
                    done
                    for suite in $suites; do
                        [[ "$suite" == kali-rolling ]] || invalid=1
                    done
                done < <(awk '
                    function emit( n, i, has_binary, type_invalid, has_content ) {
                        n = split(types, type_parts, /[[:space:]]+/)
                        has_binary = 0
                        type_invalid = 0
                        has_content = types_count + uris_count + suites_count + signed_by_count +
                                      enabled_count + trusted_count + insecure_count
                        for (i = 1; i <= n; i++) {
                            if (type_parts[i] == "deb") has_binary = 1
                            else if (type_parts[i] != "" && type_parts[i] != "deb-src") type_invalid = 1
                        }
                        if (has_content > 0 && enabled != "no") {
                            if (types_count != 1 || uris_count != 1 || suites_count != 1 || signed_by_count != 1 ||
                                enabled_count > 1 || trusted_count > 1 || insecure_count > 1 || type_invalid ||
                                (enabled != "yes" && enabled != "no") ||
                                (trusted != "" && trusted != "no" && trusted != "false" && trusted != "0") ||
                                (allow_insecure != "" && allow_insecure != "no" && allow_insecure != "false" && allow_insecure != "0") ||
                                uris == "" || suites == "" || signed_by == "") {
                                print "!invalid!|!invalid!|!invalid!|yes|yes|1"
                            } else {
                                print uris "|" suites "|" signed_by "|" trusted "|" allow_insecure "|" has_binary
                            }
                        }
                        types = uris = suites = signed_by = trusted = allow_insecure = ""
                        types_count = uris_count = suites_count = signed_by_count = 0
                        enabled_count = trusted_count = insecure_count = 0
                        enabled = "yes"
                        last = ""
                    }
                    /^[[:space:]]*#/ { next }
                    /^[[:space:]]*$/ { emit(); next }
                    {
                        key = tolower($0)
                        if (key ~ /^[[:space:]]*types:[[:space:]]*/) {
                            types_count++
                            value = $0; sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", value)
                            types = tolower(value); last = "types"; next
                        }
                        if (key ~ /^[[:space:]]*uris:[[:space:]]*/) {
                            uris_count++
                            value = $0; sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", value)
                            uris = value; last = "uris"; next
                        }
                        if (key ~ /^[[:space:]]*suites:[[:space:]]*/) {
                            suites_count++
                            value = $0; sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", value)
                            suites = value; last = "suites"; next
                        }
                        if (key ~ /^[[:space:]]*enabled:[[:space:]]*/) {
                            enabled_count++
                            value = $0; sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", value)
                            enabled = tolower(value); last = "enabled"; next
                        }
                        if (key ~ /^[[:space:]]*trusted:[[:space:]]*/) {
                            trusted_count++
                            value = $0; sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", value)
                            trusted = tolower(value); last = "trusted"; next
                        }
                        if (key ~ /^[[:space:]]*signed-by:[[:space:]]*/) {
                            signed_by_count++
                            value = $0; sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", value)
                            signed_by = value; last = "signed-by"; next
                        }
                        if (key ~ /^[[:space:]]*allow-insecure:[[:space:]]*/) {
                            insecure_count++
                            value = $0; sub(/^[[:space:]]*[^:]*:[[:space:]]*/, "", value)
                            allow_insecure = tolower(value); last = "allow-insecure"; next
                        }
                    }
                    /^[^[:space:]]/ { last = ""; next }
                    /^[[:space:]]+/ {
                        value = $0; sub(/^[[:space:]]+/, "", value)
                        if (last == "uris") uris = uris " " value
                        else if (last == "suites") suites = suites " " value
                        else if (last == "types") types = types " " value
                        next
                    }
                    END { emit() }
                ' "$file")
                ;;
            *)
                while IFS='|' read -r uri suite binary; do
                    [[ -n "$uri" && -n "$suite" && "$binary" =~ ^[01]$ ]] || { invalid=1; continue; }
                    [[ "$binary" == 1 ]] && found=1
                    case "$uri" in
                        http://http.kali.org/kali|http://http.kali.org/kali/) ;;
                        *) invalid=1 ;;
                    esac
                    [[ "$suite" == kali-rolling ]] || invalid=1
                done < <(awk '
                    {
                        sub(/^[[:space:]]+/, "", $0)
                        if ($0 ~ /^#/ || ($1 != "deb" && $1 != "deb-src")) next
                        count = split($0, fields, /[[:space:]]+/)
                        field_index = 2
                        options = ""
                        if (fields[field_index] ~ /^\[/) {
                            while (field_index <= count && fields[field_index] !~ /\]$/) {
                                options = options " " fields[field_index]
                                field_index++
                            }
                            options = options " " fields[field_index]
                            field_index++
                        }
                        options = tolower(options)
                        signed_by = ""
                        signed_by_count = gsub(/signed-by[[:space:]]*=/, "&", options)
                        if (signed_by_count > 1 || options ~ /(trusted|allow-insecure)[[:space:]]*=[[:space:]]*(yes|true|1)/) {
                            print "!invalid!|!invalid!|1"
                        } else {
                            if (signed_by_count == 1) {
                                signed_by = options
                                sub(/^.*signed-by[[:space:]]*=[[:space:]]*/, "", signed_by)
                                sub(/\].*$/, "", signed_by)
                                if (signed_by != "/usr/share/keyrings/kali-archive-keyring.gpg") {
                                    print "!invalid!|!invalid!|1"
                                    next
                                }
                            }
                            if (field_index + 1 <= count) {
                                binary = ($1 == "deb") ? 1 : 0
                                print fields[field_index] "|" fields[field_index + 1] "|" binary
                            }
                            else print "!invalid!|!invalid!|1"
                        }
                    }
                ' "$file")
                ;;
        esac
    done

    (( found > 0 && invalid == 0 ))
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
    if [[ "$SP_DISTRO_ID" == kali ]]; then
        printf '  APT pinning  : every mapped package candidate targets kali-rolling; only canonical Kali sources are accepted.\n'
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
