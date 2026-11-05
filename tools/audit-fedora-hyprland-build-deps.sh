#!/usr/bin/env bash
# Read-only Fedora source-build feasibility inventory.
# Run only inside a clean Fedora 44/45 environment after dnf5 makecache.
# This reports official enabled-repository providers; it does not install packages,
# enable repositories, or claim that a provider meets an upstream version floor.
set -uo pipefail

if ! command -v dnf5 >/dev/null 2>&1; then
    printf 'ERROR: dnf5 is required for this Fedora-only audit.\n' >&2
    exit 2
fi

query_capability() {
    local capability="$1" output
    if ! output="$(dnf5 --quiet repoquery --available --whatprovides "pkgconfig($capability)" --queryformat '%{name} %{evr}\n' 2>&1)"; then
        printf 'ERROR\t%s\t%s\n' "$capability" "$output"
        return 1
    fi
    if [[ -n "$output" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && printf 'FOUND\t%s\t%s\n' "$capability" "$line"
        done <<< "$output"
    else
        printf 'MISSING\t%s\tno enabled official-repository pkg-config provider\n' "$capability"
    fi
}

query_package() {
    local package="$1" output
    if ! output="$(dnf5 --quiet repoquery --available "$package" --queryformat '%{name} %{evr}\n' 2>&1)"; then
        printf 'ERROR\t%s\t%s\n' "$package" "$output"
        return 1
    fi
    if [[ -n "$output" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && printf 'FOUND-PACKAGE\t%s\t%s\n' "$package" "$line"
        done <<< "$output"
    else
        printf 'MISSING-PACKAGE\t%s\tno enabled official-repository candidate\n' "$package"
    fi
}

printf 'Fedora release: '
. /etc/os-release
printf '%s (%s)\n' "${PRETTY_NAME:-unknown}" "${VERSION_ID:-unknown}"
printf 'Repository scope: enabled Fedora/DNF repositories only; no third-party repositories are added.\n'
printf 'Interpretation: FOUND means a provider exists, not that its EVR satisfies the pinned CMake minimum.\n\n'

failed=0
# Pkg-config modules are taken from the pinned Hyprland v0.57.1,
# portal v1.5.0 and hyprtoolkit v0.6.0 CMake contract recorded in
# docs/PROVISIONING-ROADMAP.md.
capabilities=(
    xkbcommon wayland-server wayland-protocols libinput uuid cairo pango
    pangocairo pixman-1 xcursor libdrm libeis-1.0 gbm gio-2.0 re2
    muparser lcms2 libcanberra gl egl glesv2 glslang
    xcb xcb-render xcb-xfixes xcb-composite xcb-icccm xcb-res xcb-errors
    wayland-client wayland-scanner libpipewire-0.3 libspa-0.2
    libseat libudev libdisplay-info hwdata
    iniparser absl_flat_hash_map pugixml libzip tomlplusplus
    libjpeg libwebp libmagic libpng librsvg-2.0 sdbus-c++ udis86 libffi
)
for capability in "${capabilities[@]}"; do
    query_capability "$capability" || failed=1
done

# Build tools and the Lua 5.5 provider are checked separately because their
# availability is not fully represented by the compositor pkg-config list.
packages=(
    cmake ninja-build gcc-c++ meson pkgconf-pkg-config python3 cpio
    make readline-devel ncurses-devel git curl tar gzip xz binutils
    xorg-x11-server-Xwayland lua5.5-devel lua-devel
)
for package in "${packages[@]}"; do
    query_package "$package" || failed=1
done

printf '\nPinned Hypr* components are source inputs, not assumed Fedora RPMs:\n'
printf '%s\n' 'hyprland-protocols 0.8.0' 'hyprwayland-scanner 0.4.6' \
    'hyprutils 0.14.3' 'hyprgraphics 0.6.0' 'hyprlang 0.6.8' \
    'hyprcursor 0.1.13' 'aquamarine 0.16.0' 'hyprtoolkit 0.6.0' \
    'glaze 7.2.0' 'xdg-desktop-portal-hyprland 1.5.0' 'Hyprland 0.57.1'
printf 'See docs/PROVISIONING-ROADMAP.md for immutable commits and minimum versions.\n'

exit "$failed"
