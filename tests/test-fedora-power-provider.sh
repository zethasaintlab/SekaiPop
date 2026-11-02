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
[[ "$1" == -q && "$2" == tuned-ppd ]]
RPM

cat > "$TMP/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SP_TEST_SYSTEMCTL_LOG"
case "$1" in
    cat)
        [[ "$2" == tuned-ppd.service ]]
        ;;
    is-enabled)
        if [[ "$2" == tuned-ppd.service ]]; then
            printf 'disabled\n'
            exit 0
        fi
        exit 1
        ;;
    is-active)
        if [[ "$2" == --quiet ]]; then
            [[ "${3:-}" == power-profiles-daemon.service && "${FAKE_PPD_ACTIVE:-0}" == 1 ]]
            exit $?
        fi
        if [[ "$2" == tuned-ppd.service ]]; then
            printf 'inactive\n'
            exit 3
        fi
        printf 'inactive\n'
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

sp_fedora_tuned_ppd_installed || { printf '[FAIL] tuned-ppd package detection\n' >&2; exit 1; }
printf '[PASS] Detect installed tuned-ppd provider even when its service is inactive\n'

sp_runtime_requirement_present power-profiles-daemon || {
    printf '[FAIL] Avoid planning a conflicting power-profiles-daemon package\n' >&2
    exit 1
}
printf '[PASS] Treat installed tuned-ppd as the selected provider; do not plan a second provider\n'

: > "$SP_TEST_SYSTEMCTL_LOG"
sp_setup_services
grep -Fq 'cat tuned-ppd.service' "$SP_TEST_SYSTEMCTL_LOG" || {
    printf '[FAIL] Offer the existing tuned-ppd service for confirmation\n' >&2
    exit 1
}
if grep -Fq 'cat power-profiles-daemon.service' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not reconcile power-profiles-daemon when tuned-ppd is installed\n' >&2
    exit 1
fi
printf '[PASS] Reconcile tuned-ppd only when its provider is installed and inactive\n'

: > "$SP_TEST_SYSTEMCTL_LOG"
FAKE_PPD_ACTIVE=1 sp_setup_services
if grep -Fq 'tuned-ppd.service' "$SP_TEST_SYSTEMCTL_LOG"; then
    printf '[FAIL] Do not start tuned-ppd when power-profiles-daemon is already active\n' >&2
    exit 1
fi
printf '[PASS] Do not start tuned-ppd when the PPD service is already active\n'

printf '\nFedora power-provider fixtures passed.\n'
