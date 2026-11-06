#!/usr/bin/env bash
# Experimental Fedora host-provider capability checks.
# This module is intentionally read-only: it never installs Podman, changes repositories,
# modifies host paths, or starts a privileged container.

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
    local target="${1:-${TMPDIR:-/var/tmp}}" available required_kib=$((18 * 1024 * 1024))
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
    printf 'FEDORA_HOST_PROVIDER_PREFLIGHT_OK\tFedora-%s\t%s\trootless-podman\t%s-KiB\n' \
        "$SP_DISTRO_VERSION" "$SP_ARCH" "$available"
}
