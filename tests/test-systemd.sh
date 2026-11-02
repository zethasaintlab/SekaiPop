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
    start|enable)
        printf '%s %s\n' "$scope" "$verb${*:+ $*}" >> "$MOCK_LOG"
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
