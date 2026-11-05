#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export SEKAIPOP_INSTALLER_ROOT="$ROOT"
source "$ROOT/installer/core/main.sh"

fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$1"; }

SP_QT_VERSION=''
declare -Ag DISTRO_PACKAGE_MAP=([qt6-base]='qt6-qtbase')
sp_qt_version() { return 1; }
sp_resolve_package_spec() { printf '%s' "$1"; }
pm_get_package_version() { return 1; }

if sp_qt_shadertools_required; then
    fail 'Unknown Qt version must not be interpreted as Shader Tools being unnecessary'
else
    rc=$?
fi
[[ "$rc" == 2 ]] || fail "Expected explicit unknown status 2, got $rc"
pass 'Unknown effective Qt version has a distinct fail-closed status'

SP_ROOT="$ROOT"
SP_PROFILE_ID=fedora
SP_PROFILE=minimal
SP_NO_DESKTOP=1
SP_DISTRO_VERSION=45
sp_load_distro_profile
[[ "$SP_QT_SHADER_REQUIREMENT_UNKNOWN" == 1 ]] || fail 'Distro profile must retain the unknown shader requirement state'
SP_PROFILE_REQS=()
sp_build_package_plan
found=0
for item in "${SP_MISSING_CORE[@]}"; do
    [[ "$item" == qt6-shadertools:* ]] && found=1
done
(( found )) || fail 'Package plan must surface unknown Qt Shader Tools as an unsatisfied mandatory requirement'
pass 'Package plan reports unknown Qt Shader Tools instead of silently omitting it'

printf '\nShader planning fixtures passed.\n'
