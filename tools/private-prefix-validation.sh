#!/usr/bin/env bash
set -Eeuo pipefail
usage() { printf 'Usage: %s PREFIX INSTALL_MANIFEST [REQUIRED_ARTIFACT]\n' "$0" >&2; exit 2; }
(( $# == 2 || $# == 3 )) || usage
prefix_input=$1
manifest=$2
required=${3:-}
[[ -d "$prefix_input" && ! -L "$prefix_input" ]] || { printf 'Install prefix must be an existing non-symlink directory: %s\n' "$prefix_input" >&2; exit 2; }
[[ -f "$manifest" && ! -L "$manifest" ]] || { printf 'Install manifest must be an existing non-symlink regular file: %s\n' "$manifest" >&2; exit 2; }
command -v realpath >/dev/null 2>&1 || { printf 'realpath is required.\n' >&2; exit 2; }
prefix=$(realpath -e -- "$prefix_input")
manifest=$(realpath -e -- "$manifest")
count=0
required_seen=0
path_is_inside_prefix() { case "$1" in "$prefix"/*) return 0 ;; *) return 1 ;; esac; }
while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -n "$entry" ]] || continue
    [[ "$entry" == /* ]] || { printf 'Non-absolute install path: %s\n' "$entry" >&2; exit 1; }
    lexical=$(realpath -m -- "$entry") || { printf 'Cannot normalize path: %s\n' "$entry" >&2; exit 1; }
    path_is_inside_prefix "$lexical" || { printf 'Install path escapes private prefix: %s\n' "$entry" >&2; exit 1; }
    resolved=$(realpath -e -- "$entry") || { printf 'Installed artifact is missing or unresolved: %s\n' "$entry" >&2; exit 1; }
    path_is_inside_prefix "$resolved" || { printf 'Installed artifact resolves outside private prefix: %s -> %s\n' "$entry" "$resolved" >&2; exit 1; }
    if [[ -n "$required" && "$lexical" == "$(realpath -m -- "$required")" ]]; then required_seen=1; fi
    count=$((count + 1))
done < "$manifest"
(( count > 0 )) || { printf 'Install manifest is empty: %s\n' "$manifest" >&2; exit 1; }
if [[ -n "$required" ]]; then
    [[ "$required" == /* ]] || { printf 'Required artifact path must be absolute: %s\n' "$required" >&2; exit 2; }
    [[ "$required_seen" == 1 ]] || { printf 'Required artifact absent from install manifest: %s\n' "$required" >&2; exit 1; }
    [[ -e "$required" || -L "$required" ]] || { printf 'Required artifact does not exist: %s\n' "$required" >&2; exit 1; }
fi
printf 'PRIVATE_PREFIX_VALIDATION_OK\t%s\t%d\n' "$prefix" "$count"
