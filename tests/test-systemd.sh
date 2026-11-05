#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-systemd.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin"
export SEKAIPOP_INSTALLER_ROOT="$ROOT"
export MOCK_LOG="$TMP/actions.log"
: > "$MOCK_LOG"

cat > "$TMP/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == systemctl ]] || exit 97
shift
exec systemctl "$@"
MOCK

cat > "$TMP/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
scope=system
if [[ "${1:-}" == --user ]]; then
    scope=user
    shift
fi
verb="${1:-}"
shift || true
service="${1:-}"
case "$verb" in
	cat)
        [[ "$scope" == "${MOCK_SCOPE:-system}" && "$service" == "${MOCK_SERVICE:-}" ]]
        ;;
    is-enabled)
        [[ "$scope" == "${MOCK_SCOPE:-system}" && "$service" == "${MOCK_SERVICE:-}" ]] || exit 1
        printf '%s\n' "${MOCK_STATE:-unknown}"
        ;;
    is-active)
        [[ "$scope" == "${MOCK_SCOPE:-system}" && "$service" == "${MOCK_SERVICE:-}" ]] || exit 1
        printf '%s\n' "${MOCK_ACTIVE:-inactive}"
        ;;
    start|enable|stop|disable)
        printf '%s %s\n' "$scope" "$verb${*:+ $*}" >> "$MOCK_LOG"
        [[ "$verb" != "${MOCK_FAIL_ACTION:-}" ]] || exit 42
        if [[ "$verb" == "${MOCK_FAIL_ROLLBACK_ACTION:-}" ]]; then exit 43; fi
        ;;
    *)
        exit 1
        ;;
esac
MOCK
chmod +x "$TMP/bin/sudo" "$TMP/bin/systemctl"
export PATH="$TMP/bin:$PATH"
source "$ROOT/installer/core/main.sh"
SP_INIT=systemd
SP_YES=1
PASS=0
FAIL=0

assert_case() {
    local label="$1" scope="$2" state="$3" active="$4" expected="$5" service
    if [[ "$scope" == user ]]; then
        service=pipewire.service
        export DBUS_SESSION_BUS_ADDRESS=mock-session-bus
    else
        service=NetworkManager.service
        unset DBUS_SESSION_BUS_ADDRESS
    fi
    export MOCK_SCOPE="$scope" MOCK_SERVICE="$service" MOCK_STATE="$state" MOCK_ACTIVE="$active"
    : > "$MOCK_LOG"
    sp_setup_services >/dev/null 2>&1
    local actual
    actual="$(<"$MOCK_LOG")"
    if [[ "$actual" == "$expected" ]]; then
        printf '[PASS] %s\n' "$label"
        PASS=$((PASS + 1))
    else
        printf '[FAIL] %s (expected=%q actual=%q)\n' "$label" "$expected" "$actual" >&2
        FAIL=$((FAIL + 1))
    fi
}

assert_case 'Disabled inactive system service is enabled and started' system disabled inactive 'system enable --now NetworkManager.service'
assert_case 'Enabled inactive system service is started without re-enabling' system enabled inactive 'system start NetworkManager.service'
assert_case 'Enabled-runtime inactive system service is started' system enabled-runtime inactive 'system start NetworkManager.service'
assert_case 'Static inactive system service is started without enable' system static inactive 'system start NetworkManager.service'
assert_case 'Active disabled system service is left unchanged' system disabled active ''
assert_case 'Masked system service is left unchanged' system masked inactive ''
assert_case 'Disabled inactive user service is enabled and started' user disabled inactive 'user enable --now pipewire.service'
assert_case 'Enabled inactive user service is started without re-enabling' user enabled inactive 'user start pipewire.service'

printf '\nSystemd service assertions: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))

# Deployment transaction rollback restores each unit to its original state in reverse order.
export MOCK_SCOPE=system MOCK_SERVICE=NetworkManager.service MOCK_STATE=disabled MOCK_ACTIVE=inactive
: > "$MOCK_LOG"
sp_service_transaction_begin
sp_reconcile_service system NetworkManager.service
sp_service_transaction_rollback
expected=$'system enable --now NetworkManager.service\nsystem disable --now NetworkManager.service'
[[ "$(<"$MOCK_LOG")" == "$expected" ]] || {
    printf '[FAIL] Disabled service returns to disabled/inactive state (actual=%q)\n' "$(<"$MOCK_LOG")" >&2
    exit 1
}
printf '[PASS] Transaction rollback disables and stops a service that was originally disabled/inactive\n'

export MOCK_SCOPE=system MOCK_SERVICE=NetworkManager.service MOCK_STATE=enabled MOCK_ACTIVE=inactive
: > "$MOCK_LOG"
sp_service_transaction_begin
sp_reconcile_service system NetworkManager.service
sp_service_transaction_rollback
expected=$'system start NetworkManager.service\nsystem stop NetworkManager.service'
[[ "$(<"$MOCK_LOG")" == "$expected" ]] || {
    printf '[FAIL] Enabled service returns to its original inactive state (actual=%q)\n' "$(<"$MOCK_LOG")" >&2
    exit 1
}
printf '[PASS] Transaction rollback stops a service that was originally enabled/inactive without disabling it\n'

export MOCK_SCOPE=user MOCK_SERVICE=pipewire.service MOCK_STATE=disabled MOCK_ACTIVE=inactive DBUS_SESSION_BUS_ADDRESS=mock-session-bus
: > "$MOCK_LOG"
sp_service_transaction_begin
sp_reconcile_service user pipewire.service
sp_service_transaction_rollback
expected=$'user enable --now pipewire.service\nuser disable --now pipewire.service'
[[ "$(<"$MOCK_LOG")" == "$expected" ]] || {
    printf '[FAIL] User service returns to its original disabled/inactive state (actual=%q)\n' "$(<"$MOCK_LOG")" >&2
    exit 1
}
printf '[PASS] Transaction rollback restores user-scope systemd services\n'

export MOCK_SCOPE=system MOCK_SERVICE=NetworkManager.service MOCK_STATE=disabled MOCK_ACTIVE=inactive
: > "$MOCK_LOG"
sp_service_transaction_begin
sp_reconcile_service system NetworkManager.service
sp_service_transaction_commit
[[ "$(<"$MOCK_LOG")" == 'system enable --now NetworkManager.service' ]] ||
    { printf '[FAIL] Committed service transaction must not immediately roll back\n' >&2; exit 1; }
printf '[PASS] Successful transaction commits service changes without reverting them\n'

# A failed enable --now may have enabled the unit before the start failed.
# The reconciler must reverse that partial state before the deployment can commit.
export MOCK_SCOPE=system MOCK_SERVICE=NetworkManager.service MOCK_STATE=disabled MOCK_ACTIVE=inactive
export MOCK_FAIL_ACTION=enable MOCK_FAIL_ROLLBACK_ACTION=''
: > "$MOCK_LOG"
sp_service_transaction_begin
sp_reconcile_service system NetworkManager.service
expected=$'system enable --now NetworkManager.service\nsystem disable --now NetworkManager.service'
[[ "$(<"$MOCK_LOG")" == "$expected" ]] || {
    printf '[FAIL] Failed enable --now is immediately reversed (actual=%q)\n' "$(<"$MOCK_LOG")" >&2
    exit 1
}
[[ "${#SP_SERVICE_CHANGE_NAMES[@]}" == 0 && "$SP_SERVICE_ROLLBACK_FAILED" == 0 ]] ||
    { printf '[FAIL] Recovered partial action must be removed from the transaction journal\n' >&2; exit 1; }
sp_service_transaction_commit
printf '[PASS] Partial enable --now failure is immediately reverted before transaction commit\n'

# If the immediate reversal also fails, the entry must remain journaled and the
# caller receives a hard failure so deployment enters the full rollback path.
export MOCK_FAIL_ACTION=enable MOCK_FAIL_ROLLBACK_ACTION=disable
: > "$MOCK_LOG"
sp_service_transaction_begin
if sp_reconcile_service system NetworkManager.service; then
    printf '[FAIL] Unreverted partial service action must fail reconciliation\n' >&2
    exit 1
fi
[[ "${#SP_SERVICE_CHANGE_NAMES[@]}" == 1 && "$SP_SERVICE_ROLLBACK_FAILED" == 1 ]] ||
    { printf '[FAIL] Unreverted partial action must remain in the transaction journal\n' >&2; exit 1; }
export MOCK_FAIL_ACTION='' MOCK_FAIL_ROLLBACK_ACTION=''
sp_service_transaction_rollback
expected=$'system enable --now NetworkManager.service\nsystem disable --now NetworkManager.service\nsystem disable --now NetworkManager.service'
[[ "$(<"$MOCK_LOG")" == "$expected" ]] || {
    printf '[FAIL] Full rollback retries the incomplete service reversal (actual=%q)\n' "$(<"$MOCK_LOG")" >&2
    exit 1
}
printf '[PASS] Unreverted partial service action fails reconciliation and is retried by deployment rollback\n'
