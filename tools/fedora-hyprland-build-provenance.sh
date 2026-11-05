#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    printf 'Usage: %s OUTPUT_FILE SOURCE_DIRECTORY\n' "$0" >&2
    exit 2
}
(( $# == 2 )) || usage

OUTPUT=$1
SOURCES=$2
OS_RELEASE_FILE=${SEKAIPOP_OS_RELEASE_FILE:-/etc/os-release}
BASE_IMAGE_REF=${SEKAIPOP_BASE_IMAGE_REF:-}

[[ "$OUTPUT" == /* ]] || { printf 'Output path must be absolute.\n' >&2; exit 2; }
[[ -d "$(dirname -- "$OUTPUT")" && ! -L "$(dirname -- "$OUTPUT")" ]] || {
    printf 'Output parent must be an existing non-symlink directory.\n' >&2
    exit 2
}
[[ ! -e "$OUTPUT" && ! -L "$OUTPUT" ]] || {
    printf 'Refusing existing provenance output: %s\n' "$OUTPUT" >&2
    exit 2
}
[[ -d "$SOURCES" && ! -L "$SOURCES" ]] || {
    printf 'Source directory must be an existing non-symlink directory.\n' >&2
    exit 2
}
[[ -f "$OS_RELEASE_FILE" && ! -L "$OS_RELEASE_FILE" ]] || {
    printf 'OS release file is missing or unsafe: %s\n' "$OS_RELEASE_FILE" >&2
    exit 2
}
[[ "$BASE_IMAGE_REF" == *@sha256:* ]] || {
    printf 'SEKAIPOP_BASE_IMAGE_REF must be an immutable sha256 image reference.\n' >&2
    exit 2
}

for required in rpm dnf5 git gcc g++ cmake ninja meson pkg-config uname sha256sum; do
    command -v "$required" >/dev/null 2>&1 || {
        printf 'Missing provenance command: %s\n' "$required" >&2
        exit 2
    }
done

# os-release is a trusted operating-system metadata file, not user input.
. "$OS_RELEASE_FILE"
[[ "${ID:-}" == fedora && "${VERSION_ID:-}" =~ ^(44|45)$ ]] || {
    printf 'Unsupported provenance target: %s %s\n' "${ID:-unknown}" "${VERSION_ID:-unknown}" >&2
    exit 2
}

source_names=(
    Hyprland aquamarine hyprlang hyprcursor hyprutils hyprgraphics
    hyprwayland-scanner hyprland-protocols glaze hyprtoolkit
    xdg-desktop-portal-hyprland hyprwire udis86
)
source_commits=()
for name in "${source_names[@]}"; do
    source_path="$SOURCES/$name"
    [[ -d "$source_path" && ! -L "$source_path" ]] || {
        printf 'Pinned source directory is missing or unsafe: %s\n' "$source_path" >&2
        exit 1
    }
    commit="$(git -C "$source_path" rev-parse --verify HEAD)"
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || {
        printf 'Invalid immutable commit for %s: %s\n' "$name" "$commit" >&2
        exit 1
    }
    source_commits+=("$name"$'\t'"$commit")
done

LUA_ARCHIVE="$SOURCES/lua-5.5.1.tar.gz"
[[ -f "$LUA_ARCHIVE" && ! -L "$LUA_ARCHIVE" ]] || {
    printf 'Pinned Lua source archive is missing or unsafe.\n' >&2
    exit 1
}
lua_sha256="$(sha256sum "$LUA_ARCHIVE")"
lua_sha256="${lua_sha256%% *}"
[[ "$lua_sha256" =~ ^[0-9a-f]{64}$ ]] || {
    printf 'Invalid Lua archive SHA256.\n' >&2
    exit 1
}

rpm_inventory="$(rpm -qa --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\t%{ARCH}\n' | LC_ALL=C sort)"
[[ -n "$rpm_inventory" ]] || { printf 'RPM inventory is empty.\n' >&2; exit 1; }
repo_inventory="$(dnf5 repolist --enabled -v)"
[[ -n "$repo_inventory" ]] || { printf 'Enabled DNF repository inventory is empty.\n' >&2; exit 1; }

version_line() {
    local label=$1
    shift
    local value
    value="$("$@" 2>&1 | sed -n '1p')"
    [[ -n "$value" ]] || { printf 'Could not determine %s version.\n' "$label" >&2; return 1; }
    printf '%s=%s\n' "$label" "$value"
}

parent="$(dirname -- "$OUTPUT")"
base="$(basename -- "$OUTPUT")"
tmp="$(mktemp "$parent/.$base.tmp.XXXXXX")"
cleanup() { rm -f -- "$tmp"; }
trap cleanup EXIT

{
    printf 'schema=sekaipop-fedora-build-provenance-v1\n'
    printf 'fedora_id=%s\n' "$ID"
    printf 'fedora_version=%s\n' "$VERSION_ID"
    printf 'fedora_pretty_name=%s\n' "${PRETTY_NAME:-unknown}"
    printf 'architecture=%s\n' "$(uname -m)"
    printf 'base_image_ref=%s\n' "$BASE_IMAGE_REF"
    printf 'source_archive.lua-5.5.1.sha256=%s\n' "$lua_sha256"
    printf '\n[toolchain]\n'
    version_line gcc 'gcc' --version
    version_line gxx 'g++' -dumpfullversion -dumpversion
    version_line cmake cmake --version
    version_line ninja ninja --version
    version_line meson meson --version
    version_line pkg_config 'pkg-config' --version
    version_line git git --version
    printf '\n[source_commits]\n'
    printf '%s\n' "${source_commits[@]}"
    printf '\n[installed_rpms]\n'
    printf '%s\n' "$rpm_inventory"
    printf '\n[enabled_dnf_repositories]\n'
    printf '%s\n' "$repo_inventory"
} > "$tmp"

chmod 0644 "$tmp"
# Hard-link publication is atomic and refuses to overwrite an existing file.
ln -- "$tmp" "$OUTPUT"
rm -f -- "$tmp"
trap - EXIT
printf 'FEDORA_BUILD_PROVENANCE_OK\t%s\n' "$OUTPUT"
