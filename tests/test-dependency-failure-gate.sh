#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export SEKAIPOP_INSTALLER_ROOT="$ROOT"
source "$ROOT/installer/core/main.sh"

tmpdir="$(mktemp -d)"
marker="$tmpdir/deployment-started"
trap 'rm -rf -- "$tmpdir"' EXIT

sp_parse_args() {
    SP_RESTORE=0
    SP_SYSTEM_UPGRADE=0
    SP_CHECK=0
    SP_DRY_RUN=0
    SP_NO_DEPS=0
    SP_DEPS_ONLY=0
    SP_BACKEND=fedora
    SP_DISTRO_NAME='Test Fedora'
    SP_DISTRO_ID=fedora
    SP_DISTRO_VERSION=45
    SP_RELEASE_POLICY=test
}
sp_detect_distribution() { :; }
sp_validate_preflight() { :; }
sp_acquire_installer_lock() { :; }
sp_make_log() { :; }
sp_info() { :; }
sp_error() { :; }
sp_plan_and_install_dependencies() { return 23; }
sp_deploy_application() { : > "$marker"; }

if sekaipop_main; then
    printf '[FAIL] dependency failure unexpectedly returned success\n' >&2
    exit 1
fi

if [[ -e "$marker" ]]; then
    printf '[FAIL] application deployment ran after dependency failure\n' >&2
    exit 1
fi

printf '[PASS] dependency failure returns nonzero and prevents deployment\n'
