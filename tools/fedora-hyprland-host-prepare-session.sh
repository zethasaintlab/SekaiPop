#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX="${1:?usage: fedora-hyprland-host-prepare-session.sh STAGED_PREFIX RUNTIME_PREFIX}"
RUNTIME_PREFIX="${2:?usage: fedora-hyprland-host-prepare-session.sh STAGED_PREFIX RUNTIME_PREFIX}"
RELEASE_ID="0.57.1-acc1aa0bfd4b-portal-1.5.0-d1467fea8d18"
EXPECTED_PREFIX="/opt/sekaipop/providers/hyprland/releases/$RELEASE_ID"

[[ "$RUNTIME_PREFIX" == "$EXPECTED_PREFIX" ]] || {
    printf 'Unexpected Hyprland runtime prefix: %s\n' "$RUNTIME_PREFIX" >&2
    exit 2
}
[[ -d "$PREFIX" && ! -L "$PREFIX" ]] || {
    printf 'Staged provider prefix is missing or symlinked: %s\n' "$PREFIX" >&2
    exit 2
}

required_files=(
    bin/Hyprland
    bin/start-hyprland
    lib64/systemd/user/hyprland-session.target
    lib/systemd/user/xdg-desktop-portal-hyprland.service
    share/xdg-desktop-portal/portals/hyprland.portal
    share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service
    share/wayland-sessions/hyprland.desktop
)
for relative in "${required_files[@]}"; do
    [[ -f "$PREFIX/$relative" && ! -L "$PREFIX/$relative" ]] || {
        printf 'Required upstream Hyprland/portal artifact is missing or unsafe: %s\n' "$relative" >&2
        exit 1
    }
done
[[ -x "$PREFIX/bin/Hyprland" && -x "$PREFIX/bin/start-hyprland" ]] || {
    printf 'Hyprland and start-hyprland must be executable.\n' >&2
    exit 1
}

wrapper="$PREFIX/bin/sekaipop-hyprland-session"
desktop="$PREFIX/share/wayland-sessions/sekaipop-hyprland.desktop"
[[ ! -e "$wrapper" && ! -L "$wrapper" && ! -e "$desktop" && ! -L "$desktop" ]] || {
    printf 'Refusing to overwrite an existing SekaiPop session integration artifact.\n' >&2
    exit 1
}

created=()
cleanup() {
    local status=$?
    if (( status != 0 )); then
        for path in "${created[@]}"; do
            rm -f -- "$path"
        done
    fi
    return "$status"
}
trap cleanup EXIT

write_atomic() {
    local destination="$1" mode="$2" temporary
    temporary="$(mktemp "$(dirname -- "$destination")/.sekaipop-session.XXXXXX")"
    cat > "$temporary"
    chmod "$mode" "$temporary"
    mv -n -- "$temporary" "$destination"
    if [[ -e "$temporary" || -L "$temporary" ]]; then
        rm -f -- "$temporary"
        printf 'Refusing concurrent session integration collision: %s\n' "$destination" >&2
        return 1
    fi
    created+=("$destination")
}

write_atomic "$wrapper" 0755 <<'WRAPPER'
#!/usr/bin/env bash
set -Eeuo pipefail

PREFIX="@SEKAIPOP_PREFIX@"
export PATH="$PREFIX/bin:${PATH:-/usr/local/bin:/usr/bin}"
if [[ -n "${XDG_DATA_DIRS:-}" ]]; then
    export XDG_DATA_DIRS="$PREFIX/share:$PREFIX/lib64:$PREFIX/lib:$XDG_DATA_DIRS"
else
    export XDG_DATA_DIRS="$PREFIX/share:$PREFIX/lib64:$PREFIX/lib:/usr/local/share:/usr/share"
fi
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland

exec "$PREFIX/bin/start-hyprland" "$@"
WRAPPER
sed -i "s|@SEKAIPOP_PREFIX@|$RUNTIME_PREFIX|g" "$wrapper"

write_atomic "$desktop" 0644 <<'DESKTOP'
[Desktop Entry]
Name=SekaiPop (Hyprland)
Comment=SekaiPop managed Hyprland desktop session
Exec=@SEKAIPOP_PREFIX@/bin/sekaipop-hyprland-session
TryExec=@SEKAIPOP_PREFIX@/bin/sekaipop-hyprland-session
Type=Application
DesktopNames=Hyprland
Keywords=tiling;wayland;compositor;sekaipop;
DESKTOP
sed -i "s|@SEKAIPOP_PREFIX@|$RUNTIME_PREFIX|g" "$desktop"

trap - EXIT
printf 'FEDORA_HYPRLAND_SESSION_PREPARED\t%s\n' "$RUNTIME_PREFIX"
