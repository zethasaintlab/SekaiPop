#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-fedora-power.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

export SEKAIPOP_INSTALLER_ROOT="$ROOT"
export SP_TEST_SYSTEMCTL_LOG="$TMP/systemctl.log"
mkdir -p "$TMP/bin"

cat > "$TMP/bin/rpm" <<'RPM'
#!/usr/bin/env bash
[[ "$1" == -q ]] || exit 1
for package in ${FAKE_RPM_PACKAGES:-}; do
    [[ "$package" == "$2" ]] && exit 0
done
exit 1
RPM

cat > "$TMP/bin/busctl" <<'BUSCTL'
#!/usr/bin/env bash
case "$*" in
    *NameHasOwner*)
        if [[ "${FAKE_POWERPROFILE_API:-0}" == 1 ]]; then
            printf 'b true\n'
        else
            printf 'b false\n'
        fi
        ;;
    *introspect*)
        printf 'org.freedesktop.UPower.PowerProfiles interface\n'
        ;;
    *) exit 1 ;;
esac
BUSCTL

cat > "$TMP/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SP_TEST_SYSTEMCTL_LOG"
case "$1" in
    cat)
        case "$2" in
            tuned.service|tuned-ppd.service|tlp.service|tlp-pd.service|power-profiles-daemon.service) exit 0 ;;
            *) exit 1 ;;
        esac
        ;;
    is-enabled)
        case "$2" in
            tuned.service|tuned-ppd.service|tlp.service|tlp-pd.service|power-profiles-daemon.service)
                printf 'disabled\n'
                exit 0
                ;;
            *) exit 1
        esac
        ;;
    is-active)
        if [[ "$2" == --quiet ]]; then
            service="${3:-}"
        else
            service="$2"
        fi
        for active_service in ${FAKE_ACTIVE_SERVICES:-}; do
            if [[ "$active_service" == "$service" ]]; then
                [[ "$2" == --quiet ]] || printf 'active\n'
                exit 0
            fi
        done
        printf 'inactive\n'
        exit 3
        ;;
esac
exit 1
SYSTEMCTL
chmod +x "$TMP/bin/rpm" "$TMP/bin/busctl" "$TMP/bin/systemctl"
export PATH="$TMP/bin:/usr/bin:/bin"

source "$ROOT/installer/core/main.sh"
SP_DISTRO_ID=fedora
SP_INIT=systemd
SP_YES=0
source "$ROOT/installer/distros/fedora/packages.sh"
[[ "${DISTRO_PACKAGE_MAP[power-profiles-daemon]}" == tuned-ppd ]] || {
    printf '[FAIL] Fedora 44 must default to its native tuned-ppd package provider\\n' >&2
    exit 1
}
SP_PROFILE_REQS=(power-profiles-daemon)

assert_existing_provider_deferred() {
    sp_build_package_plan
    [[ "${#SP_PROVIDER_INSTALLED[@]}" == 1 ]] || return 1
    [[ "${#SP_INSTALL_PKGS[@]}" == 0 ]] || return 1
    [[ "${#SP_MISSING_OPTIONAL[@]}" == 0 ]]
}

FAKE_RPM_PACKAGES='tuned-ppd'
FAKE_POWERPROFILE_API=0
export FAKE_RPM_PACKAGES FAKE_POWERPROFILE_API
if sp_runtime_requirement_present power-profiles-daemon; then
    printf '[FAIL] Inactive tuned-ppd must not be reported as an active runtime API\n' >&2
    exit 1
fi
assert_existing_provider_deferred || {
    printf '[FAIL] Do not plan a second provider when inactive tuned-ppd is already installed\n' >&2
    exit 1
}
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
grep -Fq 'cat tuned.service' "$SP_TEST_SYSTEMCTL_LOG" || {
    printf '[FAIL] Offer the TuneD backend service for confirmation\n' >&2
    exit 1
}
grep -Fq 'cat tuned-ppd.service' "$SP_TEST_SYSTEMCTL_LOG" || {
    printf '[FAIL] Offer the installed tuned-ppd service for confirmation\n' >&2
    exit 1
}
if grep -Fq 'cat power-profiles-daemon.service' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not reconcile PPD alongside tuned-ppd\n' >&2
    exit 1
fi
printf '[PASS] Inactive tuned-ppd is deferred, not duplicated, and offered for activation\n'

FAKE_RPM_PACKAGES='tlp tlp-pd'
export FAKE_RPM_PACKAGES
if sp_runtime_requirement_present power-profiles-daemon; then
    printf '[FAIL] Inactive tlp-pd must not be reported as an active runtime API\n' >&2
    exit 1
fi
assert_existing_provider_deferred || {
    printf '[FAIL] Do not plan a second provider when inactive tlp-pd is already installed\n' >&2
    exit 1
}
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
grep -Fq 'cat tlp.service' "$SP_TEST_SYSTEMCTL_LOG" || {
    printf '[FAIL] Offer the TLP backend service for confirmation\n' >&2
    exit 1
}
grep -Fq 'cat tlp-pd.service' "$SP_TEST_SYSTEMCTL_LOG" || {
    printf '[FAIL] Offer the TLP profile API service for confirmation\n' >&2
    exit 1
}
if grep -Eq 'cat (tuned|power-profiles-daemon)\.service' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not reconcile another provider alongside tlp-pd\n' >&2
    exit 1
fi
printf '[PASS] Inactive tlp-pd is deferred, not duplicated, and offered with its backend\n'

FAKE_RPM_PACKAGES='tlp'
export FAKE_RPM_PACKAGES
if sp_runtime_requirement_present power-profiles-daemon; then
    printf '[FAIL] TLP without tlp-pd must not be misreported as a PowerProfiles provider\n' >&2
    exit 1
fi
sp_build_package_plan
(("${#SP_MISSING_OPTIONAL[@]}" == 1)) &&
    [[ "${SP_MISSING_OPTIONAL[0]}" == *'TLP is installed without tlp-pd'* ]] || {
    printf '[FAIL] Report TLP-only provider conflict as an unavailable optional capability\n' >&2
    exit 1
}
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
if grep -Eq 'cat (tuned|tlp-pd|power-profiles-daemon)\.service' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not add a competing provider when TLP is installed without tlp-pd\n' >&2
    exit 1
fi
printf '[PASS] TLP without tlp-pd is reported unavailable and no competing provider is added\n'

FAKE_RPM_PACKAGES='tuned-ppd'
FAKE_ACTIVE_SERVICES='tuned-ppd.service'
FAKE_POWERPROFILE_API=1
export FAKE_RPM_PACKAGES FAKE_ACTIVE_SERVICES FAKE_POWERPROFILE_API
sp_runtime_requirement_present power-profiles-daemon || {
    printf '[FAIL] Active PowerProfiles D-Bus API should satisfy the runtime capability\n' >&2
    exit 1
}
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
grep -Fq 'cat tuned.service' "$SP_TEST_SYSTEMCTL_LOG" || {
    printf '[FAIL] Keep the selected TuneD backend under service-state reconciliation\n' >&2
    exit 1
}
grep -Fq 'cat tuned-ppd.service' "$SP_TEST_SYSTEMCTL_LOG" || {
    printf '[FAIL] Keep the selected TuneD PPD service under service-state reconciliation\n' >&2
    exit 1
}
if grep -Eq 'cat (tlp|power-profiles-daemon)\.service|^(enable|start) ' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not start a competing provider or change already-active TuneD services\n' >&2
    exit 1
fi
printf '[PASS] Active TuneD provider is reconciled without starting a competing provider or changing active units\n'

FAKE_RPM_PACKAGES='tuned-ppd tlp tlp-pd'
FAKE_ACTIVE_SERVICES='power-profiles-daemon.service'
FAKE_POWERPROFILE_API=1
export FAKE_RPM_PACKAGES FAKE_ACTIVE_SERVICES FAKE_POWERPROFILE_API
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
grep -Fq 'cat power-profiles-daemon.service' "$SP_TEST_SYSTEMCTL_LOG" || {
    printf '[FAIL] Keep the already-active power-profiles-daemon provider selected when TuneD/TLP packages are also installed\n' >&2
    exit 1
}
if grep -Eq 'cat (tuned|tuned-ppd|tlp|tlp-pd)\.service|^(enable|start) ' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not activate TuneD or TLP beside an already-active PPD service\n' >&2
    exit 1
fi
printf '[PASS] Active PPD wins over inactive installed TuneD/TLP packages\n'

FAKE_RPM_PACKAGES='tuned-ppd tlp-pd'
FAKE_ACTIVE_SERVICES='tuned-ppd.service tlp-pd.service'
FAKE_POWERPROFILE_API=1
export FAKE_RPM_PACKAGES FAKE_ACTIVE_SERVICES FAKE_POWERPROFILE_API
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
if grep -Eq 'cat (tuned|tuned-ppd|tlp|tlp-pd|power-profiles-daemon)\.service|^(enable|start) ' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not modify provider services when multiple providers are already active\n' >&2
    exit 1
fi
printf '[PASS] Multiple active Fedora providers are detected and left untouched\n'

FAKE_RPM_PACKAGES='tuned-ppd tlp-pd'
FAKE_ACTIVE_SERVICES=''
FAKE_POWERPROFILE_API=0
export FAKE_RPM_PACKAGES FAKE_ACTIVE_SERVICES FAKE_POWERPROFILE_API
[[ "$(sp_fedora_power_profile_provider_count)" == 2 ]] || {
    printf '[FAIL] Count multiple installed Fedora provider packages correctly\n' >&2
    exit 1
}
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
if grep -Eq '^cat (tuned|tuned-ppd|tlp|tlp-pd|power-profiles-daemon)\.service$|^(enable|start) ' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not choose or activate an arbitrary provider when multiple installed providers are inactive\n' >&2
    exit 1
fi
printf '[PASS] Multiple installed but inactive Fedora providers are left for explicit user resolution\n'

FAKE_RPM_PACKAGES='power-profiles-daemon'
FAKE_ACTIVE_SERVICES=''
FAKE_POWERPROFILE_API=0
export FAKE_RPM_PACKAGES FAKE_ACTIVE_SERVICES FAKE_POWERPROFILE_API
if sp_runtime_requirement_present power-profiles-daemon; then
    printf '[FAIL] Inactive PPD must not be reported as an active runtime API\n' >&2
    exit 1
fi
assert_existing_provider_deferred || {
    printf '[FAIL] Do not plan a second PPD package when the package is already installed\n' >&2
    exit 1
}
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
grep -Fq 'cat power-profiles-daemon.service' "$SP_TEST_SYSTEMCTL_LOG" || {
    printf '[FAIL] Reconcile the installed power-profiles-daemon service\n' >&2
    exit 1
}
printf '[PASS] Inactive PPD is deferred and offered for activation\n'

printf '\nFedora power-provider fixtures passed.\n'
