#!/usr/bin/env bash
# Experimental Fedora host-provider capability checks.
# This module is intentionally read-only: it never installs Podman, changes repositories,
# modifies host paths, or starts a privileged container.

SP_FEDORA_HYPRLAND_RELEASE_ID="0.57.1-acc1aa0bfd4b-portal-1.5.0-d1467fea8d18"
SP_FEDORA_HYPRLAND_RELEASE_PREFIX="/opt/sekaipop/providers/hyprland/releases/$SP_FEDORA_HYPRLAND_RELEASE_ID"
SP_FEDORA_HOST_PROVIDER_REQUIRED=0
SP_FEDORA_HOST_PROVIDER_INSTALLED_BY_TRANSACTION=0

sp_fedora_host_provider_release_exists() {
    [[ -d "$SP_FEDORA_HYPRLAND_RELEASE_PREFIX" && ! -L "$SP_FEDORA_HYPRLAND_RELEASE_PREFIX" ]]
}

sp_fedora_host_provider_user_unit_dir() {
    printf '%s/systemd/user\\n' "$SP_CONFIG_HOME"
}

sp_fedora_host_provider_ready() {
    local prefix="$SP_FEDORA_HYPRLAND_RELEASE_PREFIX"
    local session="/usr/share/wayland-sessions/sekaipop-hyprland.desktop"
    local unit_dir target portal
    unit_dir="$(sp_fedora_host_provider_user_unit_dir)"
    target="$unit_dir/hyprland-session.target"
    portal="$unit_dir/xdg-desktop-portal-hyprland.service"
    sp_fedora_host_provider_release_exists || return 1
    [[ -x "$prefix/bin/Hyprland" && -x "$prefix/bin/sekaipop-hyprland-session" ]] || return 1
    [[ -f "$prefix/BUILD-PROVENANCE" && -f "$prefix/INSTALL-MANIFEST.json" ]] || return 1
    [[ -f "$session" && ! -L "$session" ]] || return 1
    grep -Fxq "Exec=$prefix/bin/sekaipop-hyprland-session" "$session" || return 1
    grep -Fxq "TryExec=$prefix/bin/sekaipop-hyprland-session" "$session" || return 1
    [[ -L "$target" && "$(readlink -- "$target")" == "$prefix/lib64/systemd/user/hyprland-session.target" ]] || return 1
    [[ -L "$portal" && "$(readlink -- "$portal")" == "$prefix/lib/systemd/user/xdg-desktop-portal-hyprland.service" ]] || return 1
    return 0
}

sp_fedora_host_provider_supported() {
    [[ "${SP_DISTRO_ID:-}" == fedora &&
       "${SP_DISTRO_VERSION:-}" =~ ^(44|45)$ &&
       "${SP_ARCH:-}" == x86_64 &&
       "${SP_INIT:-}" == systemd ]]
}

sp_fedora_host_provider_rootless_podman() {
    command -v podman >/dev/null 2>&1 || return 1
    local rootless
    rootless="$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" || return 1
    [[ "$rootless" == true ]]
}

sp_fedora_host_provider_free_space_kib() {
    local target="${1:-${TMPDIR:-/var/tmp}}" available
    [[ -d "$target" && ! -L "$target" ]] || return 1
    available="$(df -Pk -- "$target" 2>/dev/null | awk 'NR == 2 {print $4}')"
    [[ "$available" =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "$available"
}

sp_fedora_host_provider_preflight() {
    local target="${1:-/var/tmp}" available graph_root graph_available required_kib=$((18 * 1024 * 1024))
    sp_fedora_host_provider_supported || {
        printf 'Fedora host provider supports only Fedora 44/45, x86_64, systemd, mutable hosts.\n' >&2
        return 1
    }
    (( EUID != 0 )) || {
        printf 'Run the SekaiPop installer as a normal user; provider builds must remain rootless.\n' >&2
        return 1
    }
    sp_fedora_host_provider_rootless_podman || {
        printf 'A working rootless Podman installation is required for the experimental Fedora provider.\n' >&2
        return 1
    }
    available="$(sp_fedora_host_provider_free_space_kib "$target")" || {
        printf 'Cannot determine safe free space on the provider staging filesystem: %s\n' "$target" >&2
        return 1
    }
    (( available >= required_kib )) || {
        printf 'Fedora provider requires at least 18 GiB free in %s; found %s KiB.\n' "$target" "$available" >&2
        return 1
    }
    graph_root="$(podman info --format '{{.Store.GraphRoot}}' 2>/dev/null)" || {
        printf 'Cannot determine the rootless Podman storage path.\n' >&2
        return 1
    }
    [[ -n "$graph_root" && -d "$graph_root" && ! -L "$graph_root" ]] || {
        printf 'Rootless Podman reported an unsafe storage path: %s\n' "$graph_root" >&2
        return 1
    }
    graph_available="$(sp_fedora_host_provider_free_space_kib "$graph_root")" || {
        printf 'Cannot determine free space for rootless Podman storage: %s\n' "$graph_root" >&2
        return 1
    }
    (( graph_available >= required_kib )) || {
        printf 'Fedora provider requires at least 18 GiB free in Podman storage %s; found %s KiB.\n' "$graph_root" "$graph_available" >&2
        return 1
    }
    printf 'FEDORA_HOST_PROVIDER_PREFLIGHT_OK\tFedora-%s\t%s\trootless-podman\tstage=%s-KiB\tstore=%s-KiB\n' \
        "$SP_DISTRO_VERSION" "$SP_ARCH" "$available" "$graph_available"
}
