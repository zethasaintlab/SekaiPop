#!/usr/bin/env bash
set -Eeuo pipefail

ACTION="${1:?usage: fedora-hyprland-host-user-integration.sh install|remove PREFIX}"
PREFIX="${2:?usage: fedora-hyprland-host-user-integration.sh install|remove PREFIX}"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

[[ "$ACTION" == install || "$ACTION" == remove ]] || {
    printf 'Unsupported user integration action: %s\n' "$ACTION" >&2
    exit 2
}
[[ "$PREFIX" == /opt/sekaipop/providers/hyprland/releases/* && -d "$PREFIX" && ! -L "$PREFIX" ]] || {
    printf 'Refusing an invalid or unmanaged Hyprland release prefix: %s\n' "$PREFIX" >&2
    exit 2
}
command -v systemctl >/dev/null 2>&1 || {
    printf 'systemctl is required for user-session integration.\n' >&2
    exit 2
}

sources=(
    "$PREFIX/lib64/systemd/user/hyprland-session.target"
    "$PREFIX/lib/systemd/user/xdg-desktop-portal-hyprland.service"
)
destinations=(
    "$UNIT_DIR/hyprland-session.target"
    "$UNIT_DIR/xdg-desktop-portal-hyprland.service"
)
for source in "${sources[@]}"; do
    [[ -f "$source" && ! -L "$source" ]] || {
        printf 'Required provider systemd user unit is missing or unsafe: %s\n' "$source" >&2
        exit 1
    }
done

CREATED_DESTS=()
CREATED_SOURCES=()
rollback_created() {
    local index destination source
    for ((index=${#CREATED_DESTS[@]}-1; index>=0; index--)); do
        destination="${CREATED_DESTS[index]}"
        source="${CREATED_SOURCES[index]}"
        if [[ -L "$destination" && "$(readlink -- "$destination")" == "$source" ]]; then
            rm -f -- "$destination"
        fi
    done
}

if [[ "$ACTION" == install ]]; then
    mkdir -p -- "$UNIT_DIR"
    [[ -d "$UNIT_DIR" && ! -L "$UNIT_DIR" ]] || {
        printf 'Systemd user unit directory is not a real directory: %s\n' "$UNIT_DIR" >&2
        exit 1
    }

    for index in "${!sources[@]}"; do
        source="${sources[index]}"
        destination="${destinations[index]}"
        if [[ -L "$destination" ]]; then
            [[ "$(readlink -- "$destination")" == "$source" ]] || {
                rollback_created
                printf 'Conflicting systemd user unit symlink preserved: %s\n' "$destination" >&2
                exit 1
            }
            continue
        fi
        if [[ -e "$destination" ]]; then
            rollback_created
            printf 'Conflicting systemd user unit preserved: %s\n' "$destination" >&2
            exit 1
        fi
        if ! ln -s -- "$source" "$destination"; then
            if [[ -L "$destination" && "$(readlink -- "$destination")" == "$source" ]]; then
                continue
            fi
            rollback_created
            printf 'Could not create managed systemd user unit link: %s\n' "$destination" >&2
            exit 1
        fi
        CREATED_DESTS+=("$destination")
        CREATED_SOURCES+=("$source")
    done

    if ! systemctl --user daemon-reload; then
        rollback_created
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        printf 'systemd user manager rejected the Hyprland unit integration; new links were rolled back.\n' >&2
        exit 1
    fi
    printf 'FEDORA_HYPRLAND_USER_UNITS_INSTALLED\t%s\n' "$UNIT_DIR"
    exit 0
fi

conflict=0
for index in "${!sources[@]}"; do
    source="${sources[index]}"
    destination="${destinations[index]}"
    if [[ -L "$destination" ]]; then
        if [[ "$(readlink -- "$destination")" == "$source" ]]; then
            rm -f -- "$destination"
        else
            printf 'Preserving unrelated systemd user unit symlink: %s\n' "$destination" >&2
            conflict=1
        fi
    elif [[ -e "$destination" ]]; then
        printf 'Preserving unrelated systemd user unit: %s\n' "$destination" >&2
        conflict=1
    fi
done
if ! systemctl --user daemon-reload; then
    printf 'Systemd user manager could not reload after removing managed unit links.\n' >&2
    exit 1
fi
if (( conflict != 0 )); then
    exit 1
fi
printf 'FEDORA_HYPRLAND_USER_UNITS_REMOVED\t%s\n' "$UNIT_DIR"
