#!/usr/bin/env bash
sp_usage() {
    cat <<'USAGE'
SekaiPop universal installer
Usage: ./install.sh [options]
  --help                         Show this help
  --version                      Show installer version
  --check                        Read-only dependency/runtime check
  --plan                         Read-only dependency and deployment plan
  --dry-run                      Alias for --plan; performs no writes or repo refresh
  --profile minimal|standard|full Dependency profile (default: standard)
  --deps-only                    Install dependencies and system integration only
  --no-deps                      Skip package transactions
  --no-update                    Do not refresh package metadata (APT/DNF)
  --no-desktop-layer             Skip portal/font/desktop convenience packages
  --with-optional                Alias for --profile full
  --hypr full|merge|skip         Hyprland integration (default: merge)
  --restore                      Restore the latest saved configuration snapshot
  --system-upgrade               Explicitly authorize pacman -Syu on Arch-family systems
  --allow-community-repos        Consent to reviewed community repository changes (none bundled)
  --allow-community-packages     Consent to reviewed community package providers (none bundled)
  --allow-source-builds          Consent to reviewed source-build providers (none bundled)
  --yes, -y                      Accept ordinary install/service confirmations only
  --no-log                       Do not create a diagnostic log
  --rice DIR                     SekaiPop source directory (must contain shell.qml)
  --with-tests                   Include the upstream tests directory when deploying
Legacy aliases: --core-only (minimal), --hyprland-mode <mode>.
Examples:
  ./install.sh
  ./install.sh --check
  ./install.sh --plan --profile standard
  ./install.sh --profile full --hypr merge
  ./install.sh --deps-only --profile minimal
  ./install.sh --system-upgrade
USAGE
}
sp_parse_args() {
    SP_DRY_RUN=0 SP_PLAN=0 SP_CHECK=0 SP_CHECK_CORE=0 SP_YES=0 SP_NO_LOG=0
    SP_PROFILE=standard SP_HYPR=merge SP_DEPS_ONLY=0 SP_NO_DEPS=0
    SP_NO_UPDATE=0 SP_NO_DESKTOP=0 SP_SYSTEM_UPGRADE=0 SP_ARCH_SYNC_UPGRADED=0 SP_WITH_TESTS=0
    SP_ALLOW_COMMUNITY_REPOS=0 SP_ALLOW_COMMUNITY_PACKAGES=0 SP_ALLOW_SOURCE_BUILDS=0 SP_RESTORE=0 SP_RICE=''
    local arg
    while (($#)); do
        arg="$1"
        case "$arg" in
            --help|-h) sp_usage; exit 0 ;;
            --version) printf 'SekaiPop installer 2.1.0\n'; exit 0 ;;
            --check) SP_CHECK=1 ;;
            --core) SP_CHECK_CORE=1 ;;
            --no-color) SP_COLOR=0 ;;
            --plan) SP_PLAN=1; SP_DRY_RUN=1 ;;
            --dry-run) SP_DRY_RUN=1; SP_PLAN=1 ;;
            --yes|-y) SP_YES=1 ;;
            --no-log) SP_NO_LOG=1 ;;
            --deps-only) SP_DEPS_ONLY=1 ;;
            --no-deps) SP_NO_DEPS=1 ;;
            --no-update) SP_NO_UPDATE=1 ;;
            --no-desktop-layer) SP_NO_DESKTOP=1 ;;
            --with-optional) SP_PROFILE=full ;;
            --core-only) SP_PROFILE=minimal ;;
            --system-upgrade) SP_SYSTEM_UPGRADE=1 ;;
            --allow-community-repos) SP_ALLOW_COMMUNITY_REPOS=1 ;;
            --allow-community-packages) SP_ALLOW_COMMUNITY_PACKAGES=1 ;;
            --allow-source-builds) SP_ALLOW_SOURCE_BUILDS=1 ;;
            --restore) SP_RESTORE=1 ;;
            --with-tests) SP_WITH_TESTS=1 ;;
            --profile) (($# >= 2)) || sp_die '--profile requires a value.' 2; SP_PROFILE="$2"; shift ;;
            --hypr|--hyprland-mode) (($# >= 2)) || sp_die "$arg requires a value." 2; SP_HYPR="$2"; shift ;;
            --rice) (($# >= 2)) || sp_die '--rice requires a directory path.' 2; SP_RICE="$2"; shift ;;
            --) sp_die 'Positional arguments are not supported.' 2 ;;
            -*) sp_die "Unknown option: $arg (see --help)." 2 ;;
            *) sp_die "Unexpected positional argument: $arg" 2 ;;
        esac
        shift
    done
    case "$SP_PROFILE" in minimal|standard|full) ;; *) sp_die "Invalid profile '$SP_PROFILE'." 2 ;; esac
    case "$SP_HYPR" in full|merge|skip) ;; *) sp_die "Invalid --hypr mode '$SP_HYPR'." 2 ;; esac
    (( SP_CHECK + SP_PLAN + SP_RESTORE <= 1 )) || sp_die '--check, --plan/--dry-run, and --restore are mutually exclusive.' 2
    (( SP_CHECK_CORE && ! SP_CHECK )) && sp_die '--core is only valid with --check (use check-deps.sh --core).' 2
    (( SP_CHECK && (SP_DEPS_ONLY || SP_NO_DEPS || SP_SYSTEM_UPGRADE || SP_ALLOW_COMMUNITY_REPOS || SP_ALLOW_COMMUNITY_PACKAGES || SP_ALLOW_SOURCE_BUILDS) )) && sp_die '--check cannot be combined with installation authorization/options.' 2
    (( SP_DEPS_ONLY && SP_NO_DEPS )) && sp_die '--deps-only conflicts with --no-deps.' 2
    (( SP_RESTORE && (SP_DEPS_ONLY || SP_NO_DEPS || SP_SYSTEM_UPGRADE || SP_ALLOW_COMMUNITY_REPOS || SP_ALLOW_COMMUNITY_PACKAGES || SP_ALLOW_SOURCE_BUILDS) )) && sp_die '--restore cannot be combined with installation or provider options.' 2
    if (( SP_ALLOW_COMMUNITY_REPOS || SP_ALLOW_COMMUNITY_PACKAGES || SP_ALLOW_SOURCE_BUILDS )); then sp_warn 'No external package provider is currently whitelisted. Consent flags do not enable an arbitrary repository, COPR, PPA, AUR helper, or downloaded build.'; fi
}
