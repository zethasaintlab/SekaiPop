#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
source "$ROOT/installer/core/cli.sh"

sp_warn() { :; }
sp_die() { printf '%s\\n' "$1" >&2; exit "${2:-1}"; }
assert_value() {
    local expected="$1" actual="$2" label="$3"
    [[ "$actual" == "$expected" ]] || {
        printf '[FAIL] %s: expected %s, got %s\\n' "$label" "$expected" "$actual" >&2
        exit 1
    }
}

unset SP_ALLOW_SOURCE_BUILDS
sp_parse_args
assert_value 0 "$SP_ALLOW_SOURCE_BUILDS" 'default does not authorize source builds'

SP_ALLOW_SOURCE_BUILDS=1
sp_parse_args
assert_value 1 "$SP_ALLOW_SOURCE_BUILDS" 'explicit environment authorization is preserved'

SP_ALLOW_SOURCE_BUILDS=0
sp_parse_args --yes
assert_value 0 "$SP_ALLOW_SOURCE_BUILDS" '--yes does not authorize source builds'

sp_parse_args --allow-source-builds
assert_value 1 "$SP_ALLOW_SOURCE_BUILDS" 'explicit CLI authorization is accepted'

if SP_ALLOW_SOURCE_BUILDS=true bash -c '
    source "$1/installer/core/cli.sh"
    sp_warn() { :; }
    sp_die() { exit "${2:-1}"; }
    sp_parse_args
' _ "$ROOT" >/dev/null 2>&1; then
    printf '[FAIL] invalid environment authorization value was accepted\\n' >&2
    exit 1
fi

printf '[PASS] source-build authorization defaults, environment, CLI, and --yes isolation\\n'
