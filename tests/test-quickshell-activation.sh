#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-quickshell-activation.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

export SEKAIPOP_INSTALLER_ROOT="$ROOT"
export QS_CONFIG_PATH="$TMP/config/quickshell/sekaipop"
export QS_STATE_FILE="$TMP/qs-state"
export QS_EVENT_LOG="$TMP/qs-events"
export HYPRLAND_INSTANCE_SIGNATURE=sekaipop-test-session
mkdir -p "$TMP/bin" "$(dirname "$QS_CONFIG_PATH")"
cat > "$TMP/bin/qs" <<'QS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$QS_EVENT_LOG"
case "$1" in
    list)
        if [[ "$(cat "$QS_STATE_FILE")" == running ]]; then
            printf 'Instance 42: %s\n' "$QS_CONFIG_PATH"
        else
            printf 'No running instances\n'
        fi
        ;;
    kill)
        [[ "$2" == -p && "$3" == "$QS_CONFIG_PATH" ]] || exit 64
        printf 'stopped\n' > "$QS_STATE_FILE"
        ;;
    -p)
        [[ "$2" == "$QS_CONFIG_PATH" && "$3" == -n && "$4" == -d ]] || exit 64
        [[ "${QS_LAUNCH_MODE:-running}" != fail ]] || exit 70
        printf 'running\n' > "$QS_STATE_FILE"
        ;;
    *)
        exit 64
        ;;
esac
QS
chmod +x "$TMP/bin/qs"
export PATH="$TMP/bin:$PATH"

source "$ROOT/installer/core/main.sh"
pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }
sp_confirm() { return 0; }
sp_info() { :; }
sp_warn() { printf '[WARN] %s\n' "$*" >&2; }
sp_ok() { :; }
sp_error() { printf '[ERROR] %s\n' "$*" >&2; }
SP_QS_DEST="$QS_CONFIG_PATH"
SP_HYPR=merge
SP_QS_STARTUP_ATTEMPTS=2
SP_QS_STARTUP_INTERVAL=0

# A cold start is only considered successful after qs list reports the path active.
printf 'stopped\n' > "$QS_STATE_FILE"
: > "$QS_EVENT_LOG"
sp_activate_sekaipop || fail 'Cold SekaiPop activation should succeed'
[[ "${SP_QS_PREVIOUS_INSTANCE_WAS_RUNNING:-0}" == 0 ]] || fail 'Cold start must not claim a previous running instance'
[[ "$SP_QS_INSTANCE_STARTED_BY_INSTALL" == 1 ]] || fail 'Cold start must record the new instance for rollback'
grep -Fxq -- "-p $QS_CONFIG_PATH -n -d" "$QS_EVENT_LOG" || fail 'Cold start uses Quickshell path-scoped launch arguments'
pass 'Cold start verifies the path-scoped instance after daemon launch'

# Restarting an existing instance must stop and relaunch only that exact config path.
printf 'running\n' > "$QS_STATE_FILE"
: > "$QS_EVENT_LOG"
sp_activate_sekaipop || fail 'Restarting an existing SekaiPop instance should succeed'
[[ "$SP_QS_PREVIOUS_INSTANCE_WAS_RUNNING" == 1 && "$SP_QS_INSTANCE_STARTED_BY_INSTALL" == 1 ]] ||
    fail 'Restart transaction must retain both old-instance and new-instance state until manifest commit'
grep -Fxq -- "kill -p $QS_CONFIG_PATH" "$QS_EVENT_LOG" || fail 'Existing instance is stopped by config path'
grep -Fxq -- "-p $QS_CONFIG_PATH -n -d" "$QS_EVENT_LOG" || fail 'Replacement instance is started by config path'
if grep -Eq '(^|[[:space:]])(pkill|killall)([[:space:]]|$)' "$QS_EVENT_LOG"; then
    fail 'Activation must never terminate unrelated Quickshell processes'
fi
pass 'Restart remains path-scoped and records the prior instance for recovery'

# On a later deployment failure, rollback stops the new instance, restores the
# transaction snapshot, then relaunches the previous instance against restored files.
RESTORE_LOG="$TMP/restore-events"
SP_BACKUP_DIR="$TMP/backup/current-transaction"
SP_BACKUP_ROOT="$TMP/backup"
SP_YES=0
sp_restore_latest() {
    [[ "$1" == "$SP_BACKUP_DIR" ]] || fail 'Rollback must restore the exact transaction snapshot'
    printf 'restore\n' >> "$RESTORE_LOG"
    printf 'restored\n' > "$QS_STATE_FILE"
}
sp_die() { printf 'die:%s\n' "$*" >> "$RESTORE_LOG"; return 1; }
: > "$QS_EVENT_LOG"
: > "$RESTORE_LOG"
if sp_rollback_failed_deployment 'fixture deployment failure'; then
    fail 'Rollback helper should propagate its terminal failure status'
fi
[[ "$(cat "$QS_STATE_FILE")" == running ]] || fail 'The previous Quickshell instance must be running after rollback'
[[ "$SP_QS_INSTANCE_STARTED_BY_INSTALL" == 0 && "$SP_QS_PREVIOUS_INSTANCE_WAS_RUNNING" == 0 ]] ||
    fail 'Quickshell transaction flags must clear after successful process recovery'
grep -Fxq -- "kill -p $QS_CONFIG_PATH" "$QS_EVENT_LOG" || fail 'Rollback stops only the newly installed path-scoped instance'
grep -Fxq -- "-p $QS_CONFIG_PATH -n -d" "$QS_EVENT_LOG" || fail 'Rollback restarts the prior path-scoped instance'
grep -Fxq -- restore "$RESTORE_LOG" || fail 'Rollback restores the saved configuration before relaunch'
pass 'Deployment rollback restores configuration and the previously running Quickshell instance'

# A failed Quickshell launch is an activation failure, not a successful deployment.
printf 'stopped\n' > "$QS_STATE_FILE"
: > "$QS_EVENT_LOG"
export QS_LAUNCH_MODE=fail
if sp_activate_sekaipop; then
    fail 'A rejected Quickshell launch must fail activation'
fi
[[ "$SP_QS_INSTANCE_STARTED_BY_INSTALL" == 1 ]] || fail 'A failed launch attempt must remain tracked for rollback cleanup'
pass 'A rejected daemon launch is surfaced as an activation failure'

printf '\nQuickshell activation fixtures passed.\n'
