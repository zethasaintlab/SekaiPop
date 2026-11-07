#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-fedora-provider.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
export PATH="$TMP/bin:$PATH"
mkdir -p "$TMP/bin" "$TMP/staging" "$TMP/store"

source "$ROOT/installer/providers/fedora/host-provider.sh"

cat > "$TMP/bin/podman" <<'PODMAN'
#!/usr/bin/env bash
case "$1" in
    info)
        [[ "$2" == --format ]] || exit 2
        case "$3" in
            *Rootless*) printf '%s\n' "${SEKAIPOP_TEST_ROOTLESS:-true}" ;;
            *GraphRoot*) printf '%s\n' "${SEKAIPOP_TEST_GRAPHROOT:?}" ;;
            *) exit 2 ;;
        esac
        ;;
    run)
        printf '%s\n' "$*" >> "${SEKAIPOP_TEST_PODMAN_LOG:?}"
        [[ "${SEKAIPOP_TEST_RUN_FAIL:-0}" != 1 ]]
        ;;
    *)
        exit 2
        ;;
esac
PODMAN
for helper in newuidmap newgidmap; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/$helper"
    chmod +x "$TMP/bin/$helper"
done
cat > "$TMP/bin/df" <<'DF'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
case "$3" in
    *store*) available="${SEKAIPOP_TEST_STORE_FREE_KIB:-30000000}" ;;
    *) available="${SEKAIPOP_TEST_STAGE_FREE_KIB:-30000000}" ;;
esac
printf '/dev/test 40000000 1000000 %s 3%% /tmp\n' "$available"
DF
chmod +x "$TMP/bin/podman" "$TMP/bin/df"

SP_DISTRO_ID=fedora SP_DISTRO_VERSION=44 SP_ARCH=x86_64 SP_INIT=systemd
sp_fedora_host_provider_supported || { echo '[FAIL] Fedora 44 support'; exit 1; }
SP_DISTRO_VERSION=45
sp_fedora_host_provider_supported || { echo '[FAIL] Fedora 45 support'; exit 1; }
SP_DISTRO_VERSION=46
if sp_fedora_host_provider_supported; then echo '[FAIL] unsupported release accepted'; exit 1; fi
SP_DISTRO_VERSION=44
SP_ARCH=aarch64
if sp_fedora_host_provider_supported; then echo '[FAIL] unsupported architecture accepted'; exit 1; fi
SP_ARCH=x86_64

export SEKAIPOP_TEST_ROOTLESS=false
if sp_fedora_host_provider_rootless_podman; then echo '[FAIL] rootful Podman accepted'; exit 1; fi
export SEKAIPOP_TEST_ROOTLESS=true
sp_fedora_host_provider_rootless_podman || { echo '[FAIL] rootless Podman and mapping helpers detection'; exit 1; }

export SEKAIPOP_TEST_PODMAN_LOG="$TMP/podman.log"
IMAGE_DIGEST='docker.io/library/fedora@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
: > "$SEKAIPOP_TEST_PODMAN_LOG"
sp_fedora_host_provider_rootless_container_smoke "$IMAGE_DIGEST" | grep -Fq 'FEDORA_ROOTLESS_PODMAN_SMOKE_OK' || {
    echo '[FAIL] pinned-image rootless container smoke'
    exit 1
}
grep -Fq -- "run --rm --pull=never --network none --entrypoint /usr/bin/true $IMAGE_DIGEST" "$SEKAIPOP_TEST_PODMAN_LOG" || {
    echo '[FAIL] rootless smoke did not use the immutable image with networking disabled'
    exit 1
}
export SEKAIPOP_TEST_RUN_FAIL=1
if sp_fedora_host_provider_rootless_container_smoke "$IMAGE_DIGEST" >/dev/null 2>&1; then
    echo '[FAIL] failed rootless container execution was accepted'
    exit 1
fi
unset SEKAIPOP_TEST_RUN_FAIL
if sp_fedora_host_provider_rootless_container_smoke 'docker.io/library/fedora:44' >/dev/null 2>&1; then
    echo '[FAIL] mutable Fedora image reference was accepted'
    exit 1
fi
grep -Fq 'sp_fedora_host_provider_rootless_container_smoke "$BASE_IMAGE_REF"' "$ROOT/tools/fedora-hyprland-host-build.sh" || {
    echo '[FAIL] host build does not execute the rootless container smoke before compilation'
    exit 1
}

export SEKAIPOP_TEST_GRAPHROOT="$TMP/store"
export SEKAIPOP_TEST_STAGE_FREE_KIB=100000
export SEKAIPOP_TEST_STORE_FREE_KIB=30000000
if sp_fedora_host_provider_preflight "$TMP/staging" >/dev/null 2>&1; then
    echo '[FAIL] insufficient staging space accepted'
    exit 1
fi
export SEKAIPOP_TEST_STAGE_FREE_KIB=30000000
export SEKAIPOP_TEST_STORE_FREE_KIB=100000
if sp_fedora_host_provider_preflight "$TMP/staging" >/dev/null 2>&1; then
    echo '[FAIL] insufficient Podman storage space accepted'
    exit 1
fi
export SEKAIPOP_TEST_STORE_FREE_KIB=30000000
if (( EUID == 0 )); then
    echo '[SKIP] end-to-end preflight requires a normal user'
else
    sp_fedora_host_provider_preflight "$TMP/staging" | grep -Fq 'FEDORA_HOST_PROVIDER_PREFLIGHT_OK' ||
        { echo '[FAIL] valid rootless Fedora provider preflight'; exit 1; }
fi
echo '[PASS] Fedora host-provider platform, rootless Podman, and disk-space gates'
