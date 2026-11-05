#!/usr/bin/env bash
set -Eeuo pipefail

SOURCES="${SEKAIPOP_HYPR_SOURCES:-/opt/sekaipop/sources}"
WORK="${SEKAIPOP_HYPR_WORK:-/opt/sekaipop/work}"
PREFIX="${SEKAIPOP_HYPR_PREFIX:-/opt/sekaipop/prefix}"
JOBS="${BUILD_JOBS:-2}"

[[ -d "$SOURCES" && ! -L "$SOURCES" ]] || { printf 'Missing or unsafe source directory: %s\n' "$SOURCES" >&2; exit 2; }
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { printf 'BUILD_JOBS must be a positive integer.\n' >&2; exit 2; }
[[ ! -e "$WORK" && ! -L "$WORK" ]] || { printf 'Refusing existing build directory: %s\n' "$WORK" >&2; exit 2; }
[[ ! -e "$PREFIX" && ! -L "$PREFIX" ]] || { printf 'Refusing existing install prefix: %s\n' "$PREFIX" >&2; exit 2; }

mkdir -p -- "$WORK" "$PREFIX"
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib64/pkgconfig:$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$PREFIX/lib64:$PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CMAKE_PREFIX_PATH="$PREFIX${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"

for required in cmake ninja gcc g++ pkg-config git make tar sha256sum ldd readelf; do
    command -v "$required" >/dev/null 2>&1 || { printf 'Missing build tool: %s\n' "$required" >&2; exit 1; }
done

printf 'Fedora source-build smoke: '
. /etc/os-release
case "${VERSION_ID:-}" in 44|45) printf '%s\n' "$PRETTY_NAME" ;; *) printf 'unsupported Fedora release %s\n' "${VERSION_ID:-unknown}" >&2; exit 2 ;; esac

# Build the same pinned Lua 5.5.1 into a private prefix on both Fedora targets.
tar -xzf "$SOURCES/lua-5.5.1.tar.gz" -C "$WORK"
make -C "$WORK/lua-5.5.1" linux MYCFLAGS='-fPIC'
make -C "$WORK/lua-5.5.1" install INSTALL_TOP="$PREFIX"
mkdir -p "$PREFIX/lib/pkgconfig"
cat > "$PREFIX/lib/pkgconfig/lua5.5.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: Lua
Description: Lua 5.5.1
Version: 5.5.1
Libs: -L\${libdir} -llua
Cflags: -I\${includedir}
EOF
[[ "$(pkg-config --modversion lua5.5)" == 5.5.1 ]] || { printf 'Private Lua pkg-config version mismatch.\n' >&2; exit 1; }

cmake_build() {
    local name="$1"
    shift
    local build_dir="$WORK/build-$name"
    cmake -S "$SOURCES/$name" -B "$build_dir" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DCMAKE_INSTALL_BINDIR=bin \
        -DCMAKE_INSTALL_LIBEXECDIR=libexec \
        -DCMAKE_INSTALL_DATAROOTDIR=share \
        -DCMAKE_INSTALL_RPATH="$PREFIX/lib64;$PREFIX/lib" \
        -DCMAKE_BUILD_RPATH="$PREFIX/lib64;$PREFIX/lib" \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
        -DCMAKE_PREFIX_PATH="$PREFIX" \
        -DBUILD_TESTING=OFF \
        "$@"
    cmake --build "$build_dir" --parallel "$JOBS"
    cmake --install "$build_dir"
}

# Protocol XML and the scanner are installed before any dependent library.
cmake_build hyprland-protocols
cmake_build hyprwayland-scanner

# Shared libraries, in the exact dependency order established by the pinned CMake files.
cmake_build hyprutils
cmake_build hyprgraphics
cmake_build hyprlang
cmake_build hyprcursor
cmake_build aquamarine
cmake_build hyprtoolkit

# Hyprland's CMake falls back to this checked-in submodule when no suitable
# system udis86 >= 1.7.2 is found. The source was fetched at the parent's gitlink SHA.
mkdir -p "$SOURCES/Hyprland/subprojects/udis86"
[[ -z "$(find "$SOURCES/Hyprland/subprojects/udis86" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
    printf 'Refusing to overwrite populated udis86 submodule path.\n' >&2
    exit 1
}
git -C "$SOURCES/udis86" archive --format=tar HEAD | tar -x -C "$SOURCES/Hyprland/subprojects/udis86"

# The portal's stale bundled hyprland-protocols submodule is deliberately not
# populated. Its CMake must resolve the separately pinned 0.8.0 package above.
cmake_build xdg-desktop-portal-hyprland \
    -DSYSTEMD_SERVICES=ON

# Hyprland v0.57.1's hyprctl/CMakeLists.txt requires hyprwire. The immutable
# upstream flake.lock pin is built from the same hyprutils prefix and installs
# both the library pkg-config module and hyprwire-scanner used by hyprctl.
cmake_build hyprwire

# Force the pinned local Glaze source and prohibit FetchContent network access.
cmake_build Hyprland \
    -DUSE_TRACY=OFF \
    -DNO_UWSM=ON \
    -DFETCHCONTENT_SOURCE_DIR_GLAZE="$SOURCES/glaze" \
    -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_glaze=TRUE

printf '\nPinned pkg-config versions:\n'
for module in hyprland-protocols hyprwayland-scanner hyprutils hyprgraphics hyprlang hyprcursor aquamarine hyprtoolkit lua5.5; do
    version="$(pkg-config --modversion "$module")"
    printf '  %-24s %s\n' "$module" "$version"
done

printf '\nELF runtime dependency validation:\n'
for binary in "$PREFIX/bin/Hyprland" "$PREFIX/libexec/xdg-desktop-portal-hyprland"; do
    readelf -d "$binary" | grep -Fq "$PREFIX/lib64" || {
        printf 'Missing private-prefix RUNPATH/RPATH in %s\n' "$binary" >&2
        exit 1
    }
done
binaries=(
    "$PREFIX/bin/Hyprland"
    "$PREFIX/bin/start-hyprland"
    "$PREFIX/bin/hyprland-share-picker"
    "$PREFIX/libexec/xdg-desktop-portal-hyprland"
)
for binary in "${binaries[@]}"; do
    [[ -x "$binary" ]] || { printf 'Missing expected executable: %s\n' "$binary" >&2; exit 1; }
    output="$(env -u LD_LIBRARY_PATH ldd "$binary" 2>&1)"
    if grep -Fq 'not found' <<< "$output"; then
        printf 'Unresolved ELF dependency in %s:\n%s\n' "$binary" "$output" >&2
        exit 1
    fi
    printf '  OK %s\n' "$binary"
done

version_output="$("$PREFIX/bin/Hyprland" --version 2>&1)"
grep -Fq '0.57.1' <<< "$version_output" || { printf 'Unexpected Hyprland version output: %s\n' "$version_output" >&2; exit 1; }
"$PREFIX/bin/start-hyprland" --help >/dev/null

[[ -s "$PREFIX/share/wayland-sessions/hyprland.desktop" ]] || { printf 'Wayland session desktop file was not installed.\n' >&2; exit 1; }
grep -Fq "$PREFIX/bin/start-hyprland" "$PREFIX/share/wayland-sessions/hyprland.desktop"
[[ -s "$PREFIX/share/xdg-desktop-portal/portals/hyprland.portal" ]]
[[ -s "$PREFIX/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service" ]]
[[ -s "$PREFIX/lib/systemd/user/xdg-desktop-portal-hyprland.service" ]]
[[ -s "$PREFIX/lib64/systemd/user/hyprland-session.target" ]]

printf '\nFEDORA_HYPRLAND_SOURCE_BUILD_SMOKE_OK\n'
