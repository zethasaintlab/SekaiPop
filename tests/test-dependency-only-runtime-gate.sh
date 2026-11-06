#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export SEKAIPOP_INSTALLER_ROOT="$ROOT"
source "$ROOT/installer/core/main.sh"

TMP="$(mktemp -d)"
export HOME="$TMP/home" XDG_STATE_HOME="$TMP/state"
mkdir -p "$HOME"
SP_STATE_DIR="$XDG_STATE_HOME/sekaipop"
trap 'rm -rf -- "$TMP"' EXIT
marker="$TMP/desktop-integration-started"

sp_parse_args() {
    SP_RESTORE=0
    SP_SYSTEM_UPGRADE=0
    SP_CHECK=0
    SP_DRY_RUN=0
    SP_NO_DEPS=0
    SP_DEPS_ONLY=1
    SP_BACKEND=apt
}
sp_detect_distribution() {
    SP_DISTRO_NAME='Debian fixture'
    SP_DISTRO_ID=debian
    SP_RELEASE_POLICY=stable
}
sp_validate_preflight() { :; }
sp_acquire_installer_lock() { :; }
sp_make_log() { :; }
sp_info() { :; }
sp_error() { :; }
sp_plan_and_install_dependencies() { return 0; }
sp_check_all() { return 1; }
sp_dependency_only_setup() { : > "$marker"; }

if sekaipop_main; then
    printf '[FAIL] dependency-only mode returned success after runtime verification failed\n' >&2
    exit 1
fi

if [[ -e "$marker" ]]; then
    printf '[FAIL] dependency-only mode began desktop integration with an incomplete runtime\n' >&2
    exit 1
fi

[[ -n "${SP_TRANSACTION_JOURNAL:-}" ]] || { printf '[FAIL] dependency-only path did not create a transaction journal\n' >&2; exit 1; }
grep -Fqx 
status\tfailed' "$SP_TRANSACTION_JOURNAL" || { printf '[FAIL] runtime validation failure was not journaled as failed\n' >&2; exit 1; }
printf '[PASS] dependency-only mode gates desktop integration on mandatory runtime verification\n'
