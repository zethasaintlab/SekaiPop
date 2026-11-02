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

cat > "$TMP/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SP_TEST_SYSTEMCTL_LOG"
case "$1" in
    cat)
        case "$2" in
            tuned-ppd.service|tlp.service|tlp-pd.service|power-profiles-daemon.service) exit 0 ;;
            *) exit 1 ;;
        esac
        ;;
    is-enabled)
        case "$2" in
            tuned-ppd.service|tlp.service|tlp-pd.service|power-profiles-daemon.service)
                printf 'disabled\n'
                exit 0
                ;;
            *) exit 1 ;;
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
        [[ "$2" == --quiet ]] || printf 'inactive\n'
        exit 3
        ;;
esac
exit 1
SYSTEMCTL
chmod +x "$TMP/bin/rpm" "$TMP/bin/systemctl"
export PATH="$TMP/bin:/usr/bin:/bin"

source "$ROOT/installer/core/main.sh"
SP_DISTRO_ID=fedora
SP_INIT=systemd
SP_YES=0

FAKE_RPM_PACKAGES='tuned-ppd'
export FAKE_RPM_PACKAGES
sp_fedora_tuned_ppd_installed || { printf '[FAIL] tuned-ppd package detection\n' >&2; exit 1; }
sp_runtime_requirement_present power-profiles-daemon || {
    printf '[FAIL] tuned-ppd should satisfy the provider package requirement\n' >&2
    exit 1
}
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
grep -Fq 'cat tuned-ppd.service' "$SP_TEST_SYSTEMCTL_LOG" || {
    printf '[FAIL] Offer the installed tuned-ppd service for confirmation\n' >&2
    exit 1
}
if grep -Fq 'cat power-profiles-daemon.service' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not reconcile PPD alongside tuned-ppd\n' >&2
    exit 1
fi
printf '[PASS] Installed inactive tuned-ppd is reused and offered for activation\n'

FAKE_RPM_PACKAGES='tlp tlp-pd'
export FAKE_RPM_PACKAGES
sp_fedora_tlp_pd_installed || { printf '[FAIL] tlp-pd package detection\n' >&2; exit 1; }
sp_runtime_requirement_present power-profiles-daemon || {
    printf '[FAIL] tlp-pd should satisfy the provider package requirement\n' >&2
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
if grep -Eq 'cat (tuned-ppd|power-profiles-daemon)\.service' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not reconcile another provider alongside tlp-pd\n' >&2
    exit 1
fi
printf '[PASS] Installed tlp-pd is reused with its TLP backend, not a second provider\n'

FAKE_RPM_PACKAGES='tlp'
export FAKE_RPM_PACKAGES
sp_runtime_requirement_present power-profiles-daemon || {
    printf '[FAIL] TLP-only install should prevent an automatic conflicting provider transaction\n' >&2
    exit 1
}
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
if grep -Eq 'cat (tuned-ppd|tlp-pd|power-profiles-daemon)\.service' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not add a competing provider when TLP is installed without tlp-pd\n' >&2
    exit 1
fi
printf '[PASS] TLP without tlp-pd is left intact and no competing provider is added\n'

FAKE_RPM_PACKAGES='tuned-ppd'
FAKE_ACTIVE_SERVICES='power-profiles-daemon.service'
export FAKE_RPM_PACKAGES FAKE_ACTIVE_SERVICES
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
if grep -Fq 'cat tuned-ppd.service' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not start tuned-ppd while the PPD service is active\n' >&2
    exit 1
fi
printf '[PASS] Existing active PowerProfiles service prevents a second provider start\n'

FAKE_RPM_PACKAGES='power-profiles-daemon'
FAKE_ACTIVE_SERVICES=''
export FAKE_RPM_PACKAGES FAKE_ACTIVE_SERVICES
: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
grep -Fq 'cat power-profiles-daemon.service' "$SP_TEST_SYSTEMCTL_LOG" || {
    printf '[FAIL] Reconcile the installed power-profiles-daemon service\n' >&2
    exit 1
}
printf '[PASS] Existing power-profiles-daemon is reconciled when it is the selected provider\n'

printf '\nFedora power-provider fixtures passed.\n'
