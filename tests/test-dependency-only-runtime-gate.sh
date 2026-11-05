#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export SEKAIPOP_INSTALLER_ROOT="$ROOT"
source "$ROOT/installer/core/main.sh"

TMP="$(mktemp -d)"
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
sp_detect_distribution() { :; }
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

printf '[PASS] dependency-only mode gates desktop integration on mandatory runtime verification\n'
