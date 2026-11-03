#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-kali-routing.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

export SEKAIPOP_INSTALLER_ROOT="$ROOT"
export SEKAIPOP_TEST_MODE=1
source "$ROOT/installer/core/main.sh"

pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }
assert_true() {
    local label="$1"
    shift
    "$@" && pass "$label" || fail "$label"
}
assert_false() {
    local label="$1"
    shift
    if "$@"; then fail "$label"; else pass "$label"; fi
}

cat > "$TMP/kali-os-release" <<'OS'
ID=kali
VERSION_ID="2026.3"
VERSION_CODENAME=kali-rolling
PRETTY_NAME="Kali GNU/Linux 2026.3"
OS
export SEKAIPOP_TEST_OS_RELEASE="$TMP/kali-os-release"

sp_detect_distribution
[[ "$SP_BACKEND" == apt && "$SP_PROFILE_ID" == kali ]] \
    && pass 'Kali is routed only to the dedicated APT profile' \
    || fail 'Kali is routed only to the dedicated APT profile'
[[ "$SP_RELEASE_POLICY" == *kali-rolling* ]] \
    && pass 'Kali requires the exact kali-rolling codename' \
    || fail 'Kali requires the exact kali-rolling codename'

cat > "$TMP/kali-snapshot-os-release" <<'OS'
ID=kali
VERSION_ID="2026.3"
VERSION_CODENAME=kali-last-snapshot
PRETTY_NAME="Kali GNU/Linux snapshot"
OS
if SEKAIPOP_TEST_OS_RELEASE="$TMP/kali-snapshot-os-release" bash -c 'source "$SEKAIPOP_INSTALLER_ROOT/installer/core/main.sh"; sp_detect_distribution' >/dev/null 2>&1; then
    fail 'Kali last-snapshot must not pass the rolling-only release gate'
else
    pass 'Kali last-snapshot is rejected by the rolling-only release gate'
fi

source "$ROOT/installer/distros/kali/packages.sh"
for requirement in quickshell hyprland qt6-base qt6-declarative qt6-multimedia qt6-svg dbus polkit graphics-egl pipewire wireplumber pipewire-pulse network-manager bluetooth upower; do
    [[ -n "${DISTRO_PACKAGE_MAP[$requirement]:-}" ]] || fail "Kali core mapping exists for $requirement"
done
for requirement in "${!DISTRO_PACKAGE_MAP[@]}"; do
    for package_spec in ${DISTRO_PACKAGE_MAP[$requirement]}; do
        [[ "$package_spec" == */kali-rolling ]] || fail "Kali package candidate is suite-pinned: $requirement -> $package_spec"
    done
done
pass 'Every non-empty Kali package mapping is pinned to kali-rolling'

APT_ROOT="$TMP/apt"
mkdir -p "$APT_ROOT/sources.list.d"
export SEKAIPOP_TEST_APT_ROOT="$APT_ROOT"
cat > "$APT_ROOT/sources.list.d/kali.sources" <<'SRC'
Types: deb
URIs: http://http.kali.org/kali/
Suites: kali-rolling
Components: main contrib non-free non-free-firmware
Signed-By:
  /usr/share/keyrings/kali-archive-keyring.gpg
SRC
assert_true 'Canonical Kali deb822 source with a continued Signed-By field is accepted' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list.d/kali.sources" <<'SRC'
Types: deb
URIs: https://archive.kali.org/kali/
Suites: kali-rolling
Components: main contrib non-free non-free-firmware
SRC
assert_false 'Non-default archive host is rejected in favor of Kali official load balancer' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list.d/kali.sources" <<'SRC'
Types: deb
URIs: http://http.kali.org/kali/
Suites: kali-rolling
Components: main contrib non-free non-free-firmware
SRC
cat >> "$APT_ROOT/sources.list.d/kali.sources" <<'SRC'

Types: deb
URIs: http://deb.debian.org/debian/
Suites: trixie
Components: main
Enabled: no
SRC
assert_true 'Disabled foreign deb822 source does not invalidate Kali repositories' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list.d/kali.sources" <<'SRC'
Types: deb
URIs: http://http.kali.org/kali/
Suites: kali-last-snapshot
Components: main contrib non-free non-free-firmware
SRC
assert_false 'Kali last-snapshot is rejected by the kali-rolling-only package profile' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list.d/kali.sources" <<'SRC'
Types: deb
URIs: http://http.kali.org/kali/
Suites: kali-rolling
Components: main contrib non-free non-free-firmware

Types: deb
URIs: http://deb.debian.org/debian/
Suites: trixie
Components: main
SRC
assert_false 'Mixed Kali and Debian APT sources are rejected' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list.d/kali.sources" <<'SRC'
Types: deb
URIs: http://http.kali.org/kali/
Suites: kali-rolling
Components: main contrib non-free non-free-firmware

Types: deb-src
URIs: http://deb.debian.org/debian/
Suites: trixie
Components: main
SRC
assert_false 'Foreign deb-src entries are rejected because apt update also contacts them' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list.d/kali.sources" <<'SRC'
Types: deb
URIs: http://http.kali.org/kali/
Suites: kali-rolling
Components: main contrib non-free non-free-firmware

Types: deb
URIs: http://http.kali.org/kali/
Components: main
SRC
assert_false 'Active deb822 entries without a suite are rejected' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list.d/kali.sources" <<'SRC'
Types: deb
URIs: http://mirror.example.invalid/kali/
Suites: kali-rolling
Components: main
SRC
assert_false 'Unrecognized third-party Kali mirror is rejected' sp_kali_apt_sources_are_safe

rm -f "$APT_ROOT/sources.list.d/kali.sources"
cat > "$APT_ROOT/sources.list" <<'SRC'
deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware
SRC
assert_true 'Canonical legacy Kali sources.list format is accepted' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list" <<'SRC'
deb [arch=amd64 signed-by=/usr/share/keyrings/kali-archive-keyring.gpg] http://http.kali.org/kali kali-rolling main
SRC
assert_true 'Canonical legacy source with APT options is accepted' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list" <<'SRC'
deb http://http.kali.org/kali kali-rolling main
deb http://deb.debian.org/debian trixie main
SRC
assert_false 'Mixed legacy Kali and Debian sources.list entries are rejected' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list" <<'SRC'
deb http://http.kali.org/kali kali-rolling main
deb-src http://deb.debian.org/debian trixie main
SRC
assert_false 'Foreign legacy deb-src entries are rejected' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list" <<'SRC'
deb http://http.kali.org/kali kali-rolling main
deb http://http.kali.org/kali
SRC
assert_false 'Active legacy APT entries without a suite are rejected' sp_kali_apt_sources_are_safe

cat > "$APT_ROOT/sources.list" <<'SRC'
deb http://http.kali.org/kali kali-rolling main
SRC
mkdir -p "$TMP/bin"
cat > "$TMP/bin/apt-config" <<'APT'
#!/usr/bin/env bash
printf '%s\n' 'Dir "/";' 'Dir::Etc "etc/apt";' 'Dir::Etc::sourcelist "custom.list";' 'Dir::Etc::sourceparts "sources.list.d";'
APT
chmod +x "$TMP/bin/apt-config"
PATH="$TMP/bin:$PATH"
assert_false 'Non-default APT source path overrides are rejected' sp_kali_apt_sources_are_safe

printf '\nKali routing and repository policy fixtures passed.\n'
