#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-lock.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
export SEKAIPOP_INSTALLER_ROOT="$ROOT"
export XDG_RUNTIME_DIR="$TMP/runtime"
mkdir -p "$XDG_RUNTIME_DIR"

source "$ROOT/installer/core/main.sh"

pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }

(
    sp_acquire_installer_lock
    sleep 2
) &
holder=$!
for _ in {1..50}; do
    [[ -e "$XDG_RUNTIME_DIR/installer.lock" ]] && break
    sleep 0.02
done
[[ -e "$XDG_RUNTIME_DIR/installer.lock" ]] || fail 'First installer process did not create its lock file'

if (sp_acquire_installer_lock) >/dev/null 2>&1; then
    kill "$holder" 2>/dev/null || true
    fail 'A second installer transaction must not acquire the held lock'
fi
wait "$holder"
pass 'Concurrent installer transactions are serialized'

mkdir -p "$TMP/symlink-runtime"
ln -s "$TMP/attacker-target" "$TMP/symlink-runtime/installer.lock"
XDG_RUNTIME_DIR="$TMP/symlink-runtime"
export XDG_RUNTIME_DIR
if (sp_acquire_installer_lock) >/dev/null 2>&1; then
    fail 'A symlinked lock file must be rejected'
fi
pass 'Symlinked lock files are rejected'

mkdir -p "$TMP/home/.cache" "$TMP/lock-target"
ln -s "$TMP/lock-target" "$TMP/home/.cache/sekaipop"
HOME="$TMP/home" XDG_RUNTIME_DIR= bash -c 'source "$1/installer/core/main.sh"; sp_acquire_installer_lock' _ "$ROOT" >/dev/null 2>&1 && fail 'A symlinked fallback lock directory must be rejected'
pass 'Symlinked fallback lock directories are rejected'

printf '\nInstaller lock fixtures passed.\n'
