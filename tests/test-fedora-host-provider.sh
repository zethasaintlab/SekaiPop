#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-fedora-provider.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
export PATH="$TMP/bin:$PATH"
mkdir -p "$TMP/bin" "$TMP/staging"

source "$ROOT/installer/providers/fedora/host-provider.sh"

cat > "$TMP/bin/podman" <<'PODMAN'
#!/usr/bin/env bash
[[ "$1" == info && "$2" == --format ]] || exit 2
case "$3" in
    *Rootless*) printf '%s\n' "${SEKAIPOP_TEST_ROOTLESS:-true}" ;;
    *GraphRoot*) printf '%s\n' "${SEKAIPOP_TEST_GRAPHROOT:?}" ;;
    *) exit 2 ;;
esac
PODMAN
cat > "$TMP/bin/df" <<'DF'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/test 40000000 1000000 %s 3%% /tmp\n' "${SEKAIPOP_TEST_FREE_KIB:-30000000}"
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

SEKAIPOP_TEST_ROOTLESS=false
if sp_fedora_host_provider_rootless_podman; then echo '[FAIL] rootful Podman accepted'; exit 1; fi
SEKAIPOP_TEST_ROOTLESS=true
sp_fedora_host_provider_rootless_podman || { echo '[FAIL] rootless Podman detection'; exit 1; }

export SEKAIPOP_TEST_GRAPHROOT="$TMP/staging"
SEKAIPOP_TEST_FREE_KIB=100000
if sp_fedora_host_provider_preflight "$TMP/staging" >/dev/null 2>&1; then
    echo '[FAIL] insufficient staging space accepted'
    exit 1
fi
SEKAIPOP_TEST_FREE_KIB=30000000
if (( EUID == 0 )); then
    echo '[SKIP] end-to-end preflight requires a normal user'
else
    sp_fedora_host_provider_preflight "$TMP/staging" | grep -Fq 'FEDORA_HOST_PROVIDER_PREFLIGHT_OK' ||
        { echo '[FAIL] valid rootless Fedora provider preflight'; exit 1; }
fi
echo '[PASS] Fedora host-provider platform, rootless Podman, and disk-space gates'
