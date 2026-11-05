#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
export SEKAIPOP_INSTALLER_ROOT="$ROOT"

cat > "$TMP/apt-get" <<'APT_GET'
#!/usr/bin/env bash
exit "${APT_GET_STATUS:-0}"
APT_GET
chmod +x "$TMP/apt-get"
PATH="$TMP:$PATH"

source "$ROOT/installer/core/main.sh"
source "$ROOT/installer/package-managers/apt.sh"
sp_sudo() { "$@"; }

# Exercise the production dependency planner and APT backend. Only repository
# discovery and package-state queries are deterministic test fixtures.
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
SP_INSTALL_PKGS=()
SP_INSTALL_CORE=()
scenario=transaction-failure
export APT_GET_STATUS=42
plan_calls=0

sp_load_package_manager() { :; }
sp_apt_bootstrap_official_sources() { :; }
sp_load_distro_profile() { :; }
sp_build_package_plan() {
    plan_calls=$((plan_calls + 1))
    SP_MISSING_CORE=()
    SP_MISSING_OPTIONAL=()
    SP_INSTALL_PKGS=(fixture-package)
    SP_INSTALL_CORE=(fixture-package)
    if [[ "$scenario" == post-install-missing && "$plan_calls" -gt 1 ]]; then
        SP_MISSING_CORE=(hyprland)
        SP_INSTALL_PKGS=()
        SP_INSTALL_CORE=()
    fi
}
sp_print_package_plan() { :; }
sp_confirm() { return 0; }

if sp_plan_and_install_dependencies; then
    printf '[FAIL] production planner swallowed native APT transaction failure\n' >&2
    exit 1
fi
printf '[PASS] production planner propagates native APT transaction failure\n'

scenario=post-install-missing
APT_GET_STATUS=0
plan_calls=0
if sp_plan_and_install_dependencies; then
    printf '[FAIL] production planner accepted a successful APT transaction with missing mandatory requirements\n' >&2
    exit 1
fi
printf '[PASS] production planner rejects unmet mandatory requirements after a successful APT transaction\n'
