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
assert_true 'Canonical Kali archive mirror is accepted' sp_kali_apt_sources_are_safe

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

mkdir -p "$TMP/bin"
cat > "$TMP/bin/apt-config" <<'APT'
#!/usr/bin/env bash
printf '%s\\n' 'Dir::Etc "etc/apt";' 'Dir::Etc::sourcelist "custom.list";' 'Dir::Etc::sourceparts "sources.list.d";'
APT
chmod +x "$TMP/bin/apt-config"
PATH="$TMP/bin:$PATH"
assert_false 'Non-default APT source path overrides are rejected' sp_kali_apt_sources_are_safe

printf '\nKali routing and repository policy fixtures passed.\n'
