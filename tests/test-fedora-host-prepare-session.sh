#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
SCRIPT="$ROOT/tools/fedora-hyprland-host-prepare-session.sh"
TMP="$(mktemp -d /tmp/sekaipop-host-session.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
RUNTIME_PREFIX="/opt/sekaipop/providers/hyprland/releases/0.57.1-acc1aa0bfd4b-portal-1.5.0-d1467fea8d18"

make_prefix() {
    local prefix="$1"
    mkdir -p \
        "$prefix/bin" \
        "$prefix/lib64/systemd/user" \
        "$prefix/lib/systemd/user" \
        "$prefix/share/xdg-desktop-portal/portals" \
        "$prefix/share/dbus-1/services" \
        "$prefix/share/wayland-sessions"
    for path in \
        bin/Hyprland \
        bin/start-hyprland \
        lib64/systemd/user/hyprland-session.target \
        lib/systemd/user/xdg-desktop-portal-hyprland.service \
        share/xdg-desktop-portal/portals/hyprland.portal \
        share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service \
        share/wayland-sessions/hyprland.desktop; do
        printf 'fixture\n' > "$prefix/$path"
    done
    chmod 0755 "$prefix/bin/Hyprland" "$prefix/bin/start-hyprland"
}

PREFIX="$TMP/prefix"
make_prefix "$PREFIX"
bash "$SCRIPT" "$PREFIX" "$RUNTIME_PREFIX" | grep -Fq 'FEDORA_HYPRLAND_SESSION_PREPARED'
WRAPPER="$PREFIX/bin/sekaipop-hyprland-session"
DESKTOP="$PREFIX/share/wayland-sessions/sekaipop-hyprland.desktop"
[[ -x "$WRAPPER" && "$(stat -c '%a' "$WRAPPER")" == 755 ]]
[[ -f "$DESKTOP" && "$(stat -c '%a' "$DESKTOP")" == 644 ]]
grep -Fq "PREFIX=\"$RUNTIME_PREFIX\"" "$WRAPPER"
grep -Fq 'export PATH="$PREFIX/bin:${PATH:-/usr/local/bin:/usr/bin}"' "$WRAPPER"
grep -Fq 'XDG_DATA_DIRS="$PREFIX/share:$PREFIX/lib64:$PREFIX/lib:$XDG_DATA_DIRS"' "$WRAPPER"
grep -Fq 'exec "$PREFIX/bin/start-hyprland" "$@"' "$WRAPPER"
if grep -Fq 'LD_LIBRARY_PATH' "$WRAPPER"; then
    echo '[FAIL] session wrapper must not set a global library path'
    exit 1
fi
grep -Fq "Exec=$RUNTIME_PREFIX/bin/sekaipop-hyprland-session" "$DESKTOP"
grep -Fq "TryExec=$RUNTIME_PREFIX/bin/sekaipop-hyprland-session" "$DESKTOP"
grep -Fq 'DesktopNames=Hyprland' "$DESKTOP"

if bash "$SCRIPT" "$PREFIX" "$RUNTIME_PREFIX" >/dev/null 2>&1; then
    echo '[FAIL] existing session integration artifacts were overwritten'
    exit 1
fi
grep -Fq "Exec=$RUNTIME_PREFIX/bin/sekaipop-hyprland-session" "$DESKTOP"

MISSING="$TMP/missing"
make_prefix "$MISSING"
rm "$MISSING/lib64/systemd/user/hyprland-session.target"
if bash "$SCRIPT" "$MISSING" "$RUNTIME_PREFIX" >/dev/null 2>&1; then
    echo '[FAIL] missing Hyprland session target was accepted'
    exit 1
fi
[[ ! -e "$MISSING/bin/sekaipop-hyprland-session" ]]
[[ ! -e "$MISSING/share/wayland-sessions/sekaipop-hyprland.desktop" ]]

echo '[PASS] Fedora host session launcher and desktop entry are scoped, validated, and collision-safe'
