#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-pacman-safety.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

export SEKAIPOP_INSTALLER_ROOT="$ROOT"
export PACMAN_EVENT_LOG="$TMP/events.log"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/pacman" <<'PACMAN'
#!/usr/bin/env bash
printf 'pacman:%s\n' "$*" >> "$PACMAN_EVENT_LOG"
PACMAN
chmod +x "$TMP/bin/pacman"
export PATH="$TMP/bin:/usr/bin:/bin"

source "$ROOT/installer/core/main.sh"
sp_sudo() { "$@"; }

pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }

SP_SYSTEM_UPGRADE=0
SP_ARCH_SYNC_UPGRADED=0
if (pm_refresh_metadata) >/dev/null 2>&1; then
    fail '--yes or direct backend use cannot authorize pacman -Syu without --system-upgrade'
fi
[[ ! -s "$PACMAN_EVENT_LOG" ]] || fail 'Unauthorized Arch synchronization executes no package-manager command'
pass 'The pacman backend rejects repository synchronization without explicit system-upgrade authorization'

SP_BACKEND=arch
SP_DISTRO_ID=arch
SP_DISTRO_NAME='Arch Linux'
SP_SYSTEM_UPGRADE=1
SP_ARCH_SYNC_UPGRADED=0
SP_DRY_RUN=0
SP_NO_UPDATE=0
SP_YES=1
sp_load_distro_profile() { :; }
plan_calls=0
sp_build_package_plan() {
    printf 'plan\n' >> "$PACMAN_EVENT_LOG"
    plan_calls=$((plan_calls + 1))
    SP_MISSING_CORE=()
    SP_MISSING_OPTIONAL=()
    if (( plan_calls % 2 == 1 )); then
        SP_INSTALL_PKGS=(test-dependency)
        SP_INSTALL_CORE=(test-dependency)
    else
        SP_INSTALL_PKGS=()
        SP_INSTALL_CORE=()
    fi
}
sp_print_package_plan() { :; }
sp_pacman_sync_db_fresh() { return 1; }

sp_plan_and_install_dependencies
mapfile -t events < "$PACMAN_EVENT_LOG"
[[ "${#events[@]}" == 4 ]] || fail 'Stale or absent sync DB performs one full sync, plans, installs, and revalidates dependencies'
[[ "${events[0]}" == 'pacman:-Syu --needed --noconfirm' ]] || fail 'A stale or absent sync DB is recovered only through pacman -Syu --needed'
[[ "${events[1]}" == plan ]] || fail 'Package candidate resolution happens after the safe full synchronization'
[[ "${events[2]}" == 'pacman:-S --needed --noconfirm -- test-dependency' ]] || fail 'Dependencies install without repeating the full system upgrade'
[[ "${events[3]}" == plan ]] || fail 'Mandatory package state is revalidated after the package transaction'
pass 'Explicit authorization safely recovers stale or absent Arch sync databases before dependency resolution'

 : > "$PACMAN_EVENT_LOG"
plan_calls=0
SP_ARCH_SYNC_UPGRADED=0
sp_pacman_sync_db_fresh() { return 0; }
sp_plan_and_install_dependencies
mapfile -t events < "$PACMAN_EVENT_LOG"
[[ "${#events[@]}" == 3 ]] || fail 'A fresh sync DB uses one combined package transaction followed by mandatory revalidation'
[[ "${events[0]}" == plan ]] || fail 'A fresh sync DB is planned before the combined package transaction'
[[ "${events[1]}" == 'pacman:-Syu --needed --noconfirm -- test-dependency' ]] || fail 'An explicitly authorized fresh-cache install uses pacman -Syu --needed'
[[ "${events[2]}" == plan ]] || fail 'Mandatory package state is revalidated after the Arch full-upgrade transaction'
pass 'A fresh Arch sync database retains the single-transaction pacman -Syu --needed path'

: > "$PACMAN_EVENT_LOG"
plan_calls=0
SP_SYSTEM_UPGRADE=1
SP_ARCH_SYNC_UPGRADED=0
sp_pacman_sync_db_fresh() { return 1; }
pm_refresh_metadata() {
    printf 'refresh-failure\\n' >> "$PACMAN_EVENT_LOG"
    return 19
}
if sp_plan_and_install_dependencies; then
    fail 'A failed Arch full-system synchronization must abort dependency planning'
else
    refresh_status=$?
fi
[[ "$refresh_status" == 19 ]] || fail 'Arch synchronization failure preserves the package-manager exit status'
mapfile -t events < "$PACMAN_EVENT_LOG"
[[ "${#events[@]}" == 1 && "${events[0]}" == refresh-failure ]] || fail 'A failed Arch synchronization does not continue into package planning or installation'
pass 'Arch synchronization failures stop dependency planning and preserve the original status'

: > "$PACMAN_EVENT_LOG"
SP_SYSTEM_UPGRADE=0
SP_ARCH_SYNC_UPGRADED=0
sp_pacman_sync_db_fresh() { return 1; }
if (sp_plan_and_install_dependencies) > "$TMP/unauthorized.log" 2>&1; then
    fail '--yes alone must not bypass the Arch stale-database safety gate'
fi
[[ ! -s "$PACMAN_EVENT_LOG" ]] || fail 'A stale Arch sync DB without explicit authorization must not run pacman'
pass '--yes alone cannot bypass the Arch full-upgrade authorization gate'

printf '\nArch pacman safety fixtures passed.\n'
