#!/usr/bin/env bash
set -Eeuo pipefail

ACTION="${1:?usage: fedora-hyprland-host-user-integration.sh install|remove PREFIX}"
PREFIX="${2:?usage: fedora-hyprland-host-user-integration.sh install|remove PREFIX}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
UNIT_DIR="$CONFIG_HOME/systemd/user"
RELEASE_ID="0.57.1-acc1aa0bfd4b-portal-1.5.0-d1467fea8d18"
ALLOWED_PREFIX_ROOT="/opt/sekaipop/providers/hyprland/releases"
if [[ "${SEKAIPOP_TESTING:-0}" == 1 && -n "${SEKAIPOP_TEST_PREFIX_ROOT:-}" ]]; then
    ALLOWED_PREFIX_ROOT="$SEKAIPOP_TEST_PREFIX_ROOT"
fi

[[ "$ACTION" == install || "$ACTION" == remove ]] || {
    printf 'Unsupported user integration action: %s\n' "$ACTION" >&2
    exit 2
}
[[ "$CONFIG_HOME" == /* ]] || {
    printf 'XDG_CONFIG_HOME must be an absolute path: %s\n' "$CONFIG_HOME" >&2
    exit 2
}
[[ "$PREFIX" == "$ALLOWED_PREFIX_ROOT/$RELEASE_ID" && -d "$PREFIX" && ! -L "$PREFIX" ]] || {
    printf 'Refusing an invalid or unmanaged Hyprland release prefix: %s\n' "$PREFIX" >&2
    exit 2
}
if [[ "${SEKAIPOP_TESTING:-0}" != 1 ]]; then
    [[ "$(stat -c '%u' "$PREFIX")" == 0 ]] || {
        printf 'Managed Hyprland release must be root-owned: %s\n' "$PREFIX" >&2
        exit 2
    }
fi
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

# Preflight every destination before mutating any of them. A conflict must
# leave the complete managed integration intact rather than partially removing it.
for index in "${!sources[@]}"; do
    source="${sources[index]}"
    destination="${destinations[index]}"
    if [[ -L "$destination" ]]; then
        [[ "$(readlink -- "$destination")" == "$source" ]] || {
            printf 'Preserving unrelated systemd user unit symlink: %s\n' "$destination" >&2
            exit 1
        }
    elif [[ -e "$destination" ]]; then
        printf 'Preserving unrelated systemd user unit: %s\n' "$destination" >&2
        exit 1
    fi
done

REMOVED_DESTS=()
REMOVED_SOURCES=()
for index in "${!sources[@]}"; do
    source="${sources[index]}"
    destination="${destinations[index]}"
    if [[ -L "$destination" && "$(readlink -- "$destination")" == "$source" ]]; then
        REMOVED_DESTS+=("$destination")
        REMOVED_SOURCES+=("$source")
        if ! rm -f -- "$destination"; then
            rollback_failed=0
            for rollback_index in "${!REMOVED_DESTS[@]}"; do
                rollback_destination="${REMOVED_DESTS[rollback_index]}"
                rollback_source="${REMOVED_SOURCES[rollback_index]}"
                if [[ -L "$rollback_destination" && "$(readlink -- "$rollback_destination")" == "$rollback_source" ]]; then
                    continue
                fi
                if [[ -e "$rollback_destination" || -L "$rollback_destination" ]] || ! ln -s -- "$rollback_source" "$rollback_destination"; then
                    printf 'Could not restore managed systemd user unit link after removal failure: %s\n' "$rollback_destination" >&2
                    rollback_failed=1
                fi
            done
            systemctl --user daemon-reload >/dev/null 2>&1 || rollback_failed=1
            if (( rollback_failed )); then
                printf 'User unit removal failed and rollback was incomplete; inspect %s manually.\n' "$UNIT_DIR" >&2
            else
                printf 'User unit removal failed; managed links were restored.\n' >&2
            fi
            exit 1
        fi
    fi
done

if ! systemctl --user daemon-reload; then
    rollback_failed=0
    for index in "${!REMOVED_DESTS[@]}"; do
        destination="${REMOVED_DESTS[index]}"
        source="${REMOVED_SOURCES[index]}"
        if [[ -e "$destination" || -L "$destination" ]] || ! ln -s -- "$source" "$destination"; then
            printf 'Could not restore managed systemd user unit link after daemon-reload failure: %s\n' "$destination" >&2
            rollback_failed=1
        fi
    done
    systemctl --user daemon-reload >/dev/null 2>&1 || rollback_failed=1
    if (( rollback_failed )); then
        printf 'Systemd user manager reload failed and removal rollback was incomplete; inspect %s manually.\n' "$UNIT_DIR" >&2
    else
        printf 'Systemd user manager rejected removal; managed unit links were restored.\n' >&2
    fi
    exit 1
fi
printf 'FEDORA_HYPRLAND_USER_UNITS_REMOVED\t%s\n' "$UNIT_DIR"
