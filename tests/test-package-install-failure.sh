#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export SEKAIPOP_INSTALLER_ROOT="$ROOT"
source "$ROOT/installer/core/main.sh"

# Exercise the production dependency planner while replacing only its external
# package-manager/repository boundary with deterministic failure fixtures.
SP_DRY_RUN=0
SP_BACKEND=apt
SP_NO_UPDATE=1
SP_APT_BOOTSTRAP_CREATED=()
SP_DISTRO_ID=debian
SP_DISTRO_NAME='Debian fixture'
SP_YES=1
SP_SYSTEM_UPGRADE=0
SP_MISSING_CORE=()
SP_MISSING_OPTIONAL=()
SP_INSTALL_PKGS=(fixture-package)

sp_load_package_manager() { :; }
sp_apt_bootstrap_official_sources() { :; }
sp_load_distro_profile() { :; }
sp_build_package_plan() {
    SP_MISSING_CORE=()
    SP_MISSING_OPTIONAL=()
    SP_INSTALL_PKGS=(fixture-package)
}
sp_print_package_plan() { :; }
sp_confirm() { return 0; }
pm_install() { return 42; }

if sp_plan_and_install_dependencies; then
    printf '[FAIL] production dependency planner swallowed pm_install failure\n' >&2
    exit 1
fi

printf '[PASS] production dependency planner propagates native package transaction failure\n'
