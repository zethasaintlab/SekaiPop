#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
export SEKAIPOP_INSTALLER_ROOT="$ROOT" SP_APT_SOURCES_DIR="$TMP/sources" SP_APT_MAIN_SOURCES="$TMP/sources.list"
mkdir -p "$SP_APT_SOURCES_DIR"
source "$ROOT/installer/core/common.sh"
source "$ROOT/installer/provisioning/apt-repositories.sh"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }
expect_rejected() {
    local distro="$1" version="$2" codename="$3"
    if (SP_BACKEND=apt SP_DISTRO_ID="$distro" SP_DISTRO_VERSION="$version" SP_DISTRO_CODENAME="$codename" sp_apt_validate_required_sources) >/dev/null 2>&1; then
        fail "Missing official repositories were accepted for $distro $version"
    fi
}
SP_BACKEND=apt SP_DISTRO_ID=debian SP_DISTRO_VERSION=13 SP_DISTRO_CODENAME=trixie
expect_rejected debian 13 trixie
[[ ! -e "$SP_APT_SOURCES_DIR/sekaipop-trixie-backports.sources" ]] || fail 'Validation unexpectedly created a Debian source file'
sp_apt_report_required_sources >/dev/null 2>&1
[[ -z "$(find "$SP_APT_SOURCES_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]] || fail 'Read-only plan modified the source directory'
pass 'Missing Debian backports is rejected without changing APT configuration'
cat > "$SP_APT_SOURCES_DIR/debian.sources" <<'SOURCE'
Types: deb
URIs:
 https://deb.debian.org/debian
Suites:
 trixie-backports
Components:
 main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCE
sp_apt_validate_required_sources
pass 'Deb822 folded continuation fields are parsed'
cat > "$SP_APT_SOURCES_DIR/debian.sources" <<'SOURCE'
Types: deb-src
URIs: https://deb.debian.org/debian
Suites: trixie-backports
Components: main
SOURCE
expect_rejected debian 13 trixie
pass 'Deb822 source-only deb-src stanzas do not satisfy binary package repositories'
cat > "$SP_APT_SOURCES_DIR/debian.sources" <<'SOURCE'
Types: deb deb-src
URIs: https://deb.debian.org/debian/
Suites: trixie-backports
Components: main
SOURCE
sp_apt_validate_required_sources
pass 'Deb822 mixed deb/deb-src stanzas and canonical trailing-slash URIs are accepted'
cat > "$SP_APT_SOURCES_DIR/debian.sources" <<'SOURCE'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie-backports
Components: main
Trusted: yes
SOURCE
expect_rejected debian 13 trixie
pass 'Deb822 trusted=yes sources cannot satisfy official repository validation'
cat > "$SP_APT_SOURCES_DIR/debian.sources" <<'SOURCE'
Types: deb
URIs: https://mirror.example.invalid/debian
Suites: trixie-backports
Components: main
SOURCE
expect_rejected debian 13 trixie
pass 'Third-party Debian mirrors do not satisfy official backports'
cat > "$SP_APT_SOURCES_DIR/debian.sources" <<'SOURCE'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie-backports
Components: main
Enabled: no
SOURCE
expect_rejected debian 13 trixie
pass 'Disabled Debian Deb822 stanzas are rejected'
cat > "$SP_APT_SOURCES_DIR/legacy.list" <<'SOURCE'
deb-src https://deb.debian.org/debian trixie-backports main
SOURCE
expect_rejected debian 13 trixie
pass 'Legacy deb-src entries do not satisfy binary package repositories'
cat > "$SP_APT_SOURCES_DIR/legacy.list" <<'SOURCE'
deb [trusted=yes] https://deb.debian.org/debian trixie-backports main
SOURCE
expect_rejected debian 13 trixie
pass 'Legacy trusted=yes sources cannot satisfy official repository validation'
cat > "$SP_APT_SOURCES_DIR/legacy.list" <<'SOURCE'
deb https://deb.debian.org/debian/ trixie-backports main
SOURCE
sp_apt_validate_required_sources
pass 'Legacy official archive URI trailing slashes are normalized'
cat > "$SP_APT_SOURCES_DIR/legacy.list" <<'SOURCE'
# trixie-backports main
deb [arch=amd64 signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://deb.debian.org/debian trixie-backports main contrib
SOURCE
sp_apt_validate_required_sources
pass 'Legacy APT list entries with options are recognized'
SP_DISTRO_ID=ubuntu SP_DISTRO_VERSION=26.10 SP_DISTRO_CODENAME=stonking
expect_rejected ubuntu 26.10 stonking
cat > "$SP_APT_SOURCES_DIR/ubuntu.sources" <<'SOURCE'
Types: deb
URIs: https://archive.ubuntu.com/ubuntu
Suites: stonking stonking-updates
Components: main universe

Types: deb
URIs: https://security.ubuntu.com/ubuntu
Suites: stonking-security
Components: main universe
SOURCE
sp_apt_validate_required_sources
pass 'Ubuntu Universe is accepted only for release, updates, and security'
cat > "$SP_APT_SOURCES_DIR/ubuntu.sources" <<'SOURCE'
Types: deb
URIs: https://archive.ubuntu.com/ubuntu
Suites: stonking stonking-updates
Components: main
Types: deb
URIs: https://security.ubuntu.com/ubuntu
Suites: stonking-security
Components: main
SOURCE
expect_rejected ubuntu 26.10 stonking
pass 'Ubuntu main without Universe is rejected'
cat > "$SP_APT_SOURCES_DIR/ubuntu.sources" <<'SOURCE'
Types: deb
URIs: https://archive.ubuntu.com/ubuntu
Suites: stonking stonking-updates
Components: main universe
Enabled: no

Types: deb
URIs: https://security.ubuntu.com/ubuntu
Suites: stonking-security
Components: main universe
Enabled: no
SOURCE
expect_rejected ubuntu 26.10 stonking
pass 'Disabled Ubuntu Universe stanzas are rejected'
cat > "$SP_APT_SOURCES_DIR/ubuntu.list" <<'SOURCE'
deb https://archive.ubuntu.com/ubuntu stonking main universe
deb https://archive.ubuntu.com/ubuntu stonking-updates main universe
deb https://security.ubuntu.com/ubuntu stonking-security main universe
SOURCE
sp_apt_validate_required_sources
pass 'Legacy Ubuntu list entries are recognized'
printf 'APT repository validation assertions: all passed\n'
