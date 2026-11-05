#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-power-api.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
export SEKAIPOP_INSTALLER_ROOT="$ROOT"
source "$ROOT/installer/core/main.sh"

fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$1"; }

SP_DISTRO_ID=debian
sp_have() { [[ "$1" == busctl ]]; }
OWNER_REPLY='b false'
INTERFACE_REPLY=''
busctl() {
    case "$*" in
        *NameHasOwner*) printf '%s\n' "$OWNER_REPLY" ;;
        *introspect*) printf '%s\n' "$INTERFACE_REPLY" ;;
        *) return 2 ;;
    esac
}
systemctl() {
    [[ "$1" == is-active ]] || return 1
    case "$3" in
        tlp.service) return 0 ;;
        tlp-pd.service) return 1 ;;
        *) return 1 ;;
    esac
}

if sp_runtime_requirement_present power-profiles-daemon; then
    fail 'A client executable or inactive provider must not satisfy the runtime API requirement'
fi
pass 'PowerProfiles is not considered present when no service owns its D-Bus name'

OWNER_REPLY='b true'
if sp_runtime_requirement_present power-profiles-daemon; then
    fail 'D-Bus name ownership alone is insufficient without the expected interface'
fi
pass 'PowerProfiles D-Bus name ownership is not sufficient without the exported interface'

INTERFACE_REPLY='org.freedesktop.UPower.PowerProfiles interface'
sp_runtime_requirement_present power-profiles-daemon || fail 'The expected D-Bus API should satisfy the capability on Debian'
pass 'The actual PowerProfiles D-Bus API satisfies the capability on non-Fedora systems'

SP_DISTRO_ID=fedora
sp_fedora_power_profile_api_available || fail 'Fedora wrapper should use the same D-Bus API check'
pass 'Fedora provider detection delegates to the shared D-Bus API check'

SP_DISTRO_ID=ubuntu
if sp_fedora_power_profile_api_available; then
    fail 'Fedora-specific wrapper must reject non-Fedora systems'
fi
pass 'Fedora-specific provider wrapper remains distro-scoped'

SP_DISTRO_ID=debian
OWNER_REPLY='b false'
declare -gA DISTRO_PACKAGE_MAP=(['power-profiles-daemon']='power-profiles-daemon')
SP_PROFILE_REQS=(power-profiles-daemon)
sp_resolve_package_spec() { printf '%s' "$1"; }
pm_query_installed() { return 1; }
sp_build_package_plan
[[ "${#SP_INSTALL_PKGS[@]}" == 0 ]] || fail 'Do not install PPD beside active TLP without the tlp-pd adapter'
conflict_found=0
for item in "${SP_MISSING_OPTIONAL[@]}"; do
    [[ "$item" == *'TLP is active without an active tlp-pd adapter'* ]] && conflict_found=1
done
(( conflict_found )) || fail 'The package plan must explain why the PPD provider was skipped'
pass 'Non-Fedora package planning skips conflicting PPD when TLP is active without tlp-pd'

printf '\nPowerProfiles API fixtures passed.\n'
