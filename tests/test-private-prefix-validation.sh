#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
VALIDATOR="$ROOT/tools/private-prefix-validation.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }
expect_fail() { local label=$1; shift; if "$@" >/dev/null 2>&1; then fail "$label"; else pass "$label"; fi; }
PREFIX="$TMP/prefix"
mkdir -p "$PREFIX/bin" "$PREFIX/lib"
printf '#!/bin/sh\n' > "$PREFIX/bin/demo"
printf 'library\n' > "$PREFIX/lib/demo.so"
chmod +x "$PREFIX/bin/demo"
MANIFEST="$TMP/install_manifest.txt"
printf '%s\n%s\n' "$PREFIX/bin/demo" "$PREFIX/lib/demo.so" > "$MANIFEST"
"$VALIDATOR" "$PREFIX" "$MANIFEST" "$PREFIX/bin/demo" | grep -Fq 'PRIVATE_PREFIX_VALIDATION_OK' || fail 'valid manifest accepted'
pass 'valid manifest accepted'
mkdir -p "$PREFIX/lib/normalized"
printf '%s\n' "$PREFIX/lib/normalized/../demo.so" > "$MANIFEST"
"$VALIDATOR" "$PREFIX" "$MANIFEST" >/dev/null || fail 'normalized in-prefix path accepted'
pass 'normalized in-prefix path accepted'
printf '%s\n' "$TMP/outside" > "$MANIFEST"
printf 'outside\n' > "$TMP/outside"
expect_fail 'outside path rejected' "$VALIDATOR" "$PREFIX" "$MANIFEST"
printf '%s\n' "$PREFIX/../outside" > "$MANIFEST"
expect_fail 'lexical traversal rejected' "$VALIDATOR" "$PREFIX" "$MANIFEST"
ln -s "$TMP/outside" "$PREFIX/bin/escape"
printf '%s\n' "$PREFIX/bin/escape" > "$MANIFEST"
expect_fail 'symlink resolving outside prefix rejected' "$VALIDATOR" "$PREFIX" "$MANIFEST"
printf '%s\n' "$PREFIX/bin/missing" > "$MANIFEST"
expect_fail 'missing artifact rejected' "$VALIDATOR" "$PREFIX" "$MANIFEST"
printf '%s\n' "$PREFIX/lib/demo.so" > "$MANIFEST"
expect_fail 'required artifact missing from manifest rejected' "$VALIDATOR" "$PREFIX" "$MANIFEST" "$PREFIX/bin/demo"
ln -s "$PREFIX" "$TMP/prefix-link"
expect_fail 'symlinked prefix rejected' "$VALIDATOR" "$TMP/prefix-link" "$MANIFEST"
ln -s "$MANIFEST" "$TMP/manifest-link"
expect_fail 'symlinked manifest rejected' "$VALIDATOR" "$PREFIX" "$TMP/manifest-link"
: > "$MANIFEST"
expect_fail 'empty manifest rejected' "$VALIDATOR" "$PREFIX" "$MANIFEST"
printf '\nPrivate-prefix validation fixtures passed.\n'
