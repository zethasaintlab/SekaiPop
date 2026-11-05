#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT

export SEKAIPOP_INSTALLER_ROOT="$ROOT"
export SP_APT_SOURCES_DIR="$TMP/sources"
export SP_APT_MAIN_SOURCES="$TMP/sources.list"
mkdir -p "$SP_APT_SOURCES_DIR"
source "$ROOT/installer/core/common.sh"
source "$ROOT/installer/provisioning/apt-repositories.sh"

sp_sudo() { "$@"; }
sp_confirm() { return 0; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

SP_BACKEND=apt SP_DISTRO_ID=debian SP_DISTRO_VERSION=13 SP_DISTRO_CODENAME=trixie
sp_apt_bootstrap_official_sources
debian_source="$SP_APT_SOURCES_DIR/sekaipop-trixie-backports.sources"
[[ -f "$debian_source" ]] || fail 'Debian backports source was not created'
grep -Fq 'URIs: https://deb.debian.org/debian' "$debian_source" || fail 'Debian source does not use the official archive'
grep -Fq 'Suites: trixie-backports' "$debian_source" || fail 'Debian backports suite is incorrect'
grep -Fq 'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg' "$debian_source" || fail 'Debian archive keyring is not pinned'
[[ "${#SP_APT_BOOTSTRAP_CREATED[@]}" == 1 ]] || fail 'New Debian source was not tracked for rollback'
pass 'Debian 13 official backports source is provisioned and tracked'

sp_apt_bootstrap_rollback
[[ ! -e "$debian_source" ]] || fail 'Rollback did not remove the installer-managed Debian source'
pass 'APT source rollback removes only newly managed source'

sp_apt_bootstrap_official_sources
printf '%s\\n' '# user edit during package transaction' >> "$debian_source"
sp_apt_bootstrap_rollback
grep -Fq 'user edit during package transaction' "$debian_source" || fail 'Rollback removed a source file modified after creation'
pass 'APT source rollback preserves files edited during the transaction'
rm -f -- "$debian_source"

cat > "$debian_source" <<'SOURCE'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie-backports
Components: main
SOURCE
sp_apt_bootstrap_official_sources
[[ "${#SP_APT_BOOTSTRAP_CREATED[@]}" == 0 ]] || fail 'Idempotent Debian bootstrap incorrectly marked existing source as newly created'
[[ -f "$debian_source" ]] || fail 'Existing Debian source was modified or removed'
pass 'Debian backports bootstrap is idempotent'

cat > "$SP_APT_SOURCES_DIR/untrusted-backports.sources" <<'SOURCE'
Types: deb
URIs: https://mirror.attacker.example/debian
Suites: trixie-backports
Components: main
SOURCE
if sp_apt_sources_has_suite_component trixie-backports main https://deb.debian.org/debian; then fail 'Third-party Debian mirror incorrectly satisfied the official archive requirement'; fi
sp_apt_bootstrap_official_sources
[[ -f "$debian_source" ]] || fail 'An untrusted mirror prevented official Debian source bootstrap'
sp_apt_bootstrap_rollback
rm -f -- "$SP_APT_SOURCES_DIR/untrusted-backports.sources"
pass 'Debian suite matching requires the canonical official archive URI'

rm -f -- "$debian_source"
printf '%s\n' '# trixie-backports is mentioned only in this comment' > "$SP_APT_MAIN_SOURCES"
if sp_apt_sources_has_suite_component trixie-backports main; then fail 'Comment was incorrectly treated as an enabled APT suite'; fi
pass 'APT source detection ignores commented examples'

cat > "$SP_APT_SOURCES_DIR/legacy.list" <<'SOURCE'
# example comment
deb [arch=amd64 signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://deb.debian.org/debian trixie-backports main contrib
deb https://archive.ubuntu.com/ubuntu jammy universe
SOURCE
sp_apt_sources_has_suite_component trixie-backports main https://deb.debian.org/debian || fail 'Legacy APT list entry with options and official URI was not parsed'
sp_apt_sources_has_suite_component jammy universe https://archive.ubuntu.com/ubuntu || fail 'Legacy APT list second line with official URI was not parsed'
if sp_apt_sources_has_suite_component stonking universe https://archive.ubuntu.com/ubuntu; then fail 'Universe from a different Ubuntu suite was treated as Stonking Universe'; fi
pass 'Legacy APT list parsing is line-scoped and suite-specific'
rm -f -- "$SP_APT_SOURCES_DIR/legacy.list"

SP_DISTRO_ID=ubuntu SP_DISTRO_VERSION=26.10 SP_DISTRO_CODENAME=stonking
cat > "$SP_APT_SOURCES_DIR/disabled-universe.sources" <<'SOURCE'
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
if sp_apt_sources_has_suite_component stonking universe https://archive.ubuntu.com/ubuntu; then fail 'Disabled or third-party Universe was incorrectly treated as official'; fi
sp_apt_bootstrap_official_sources
ubuntu_source="$SP_APT_SOURCES_DIR/sekaipop-universe.sources"
[[ -f "$ubuntu_source" ]] || fail 'Ubuntu Universe source was not created'
grep -Fq 'URIs: https://archive.ubuntu.com/ubuntu' "$ubuntu_source" || fail 'Ubuntu source does not use the official archive'
grep -Fq 'Suites: stonking stonking-updates' "$ubuntu_source" || fail 'Ubuntu release/update suites are incorrect'
grep -Fq 'URIs: https://security.ubuntu.com/ubuntu' "$ubuntu_source" || fail 'Ubuntu security archive is missing'
grep -Fq 'Suites: stonking-security' "$ubuntu_source" || fail 'Ubuntu security suite is incorrect'
grep -Fq 'Components: main universe' "$ubuntu_source" || fail 'Ubuntu source must provide main and Universe when no existing main component is configured'
grep -Fq 'Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg' "$ubuntu_source" || fail 'Ubuntu archive keyring is not pinned'
pass 'Ubuntu 26.10 Universe source includes official release and security archives'

sp_apt_bootstrap_rollback
[[ ! -e "$ubuntu_source" ]] || fail 'Rollback did not remove the installer-managed Ubuntu source'
pass 'Ubuntu source rollback succeeds'

cat > "$SP_APT_SOURCES_DIR/existing-main.sources" <<'SOURCE'
Types: deb
URIs: https://archive.ubuntu.com/ubuntu
Suites: stonking stonking-updates
Components: main

Types: deb
URIs: https://security.ubuntu.com/ubuntu
Suites: stonking-security
Components: main
SOURCE
sp_apt_bootstrap_official_sources
grep -Fq 'Components: universe' "$ubuntu_source" || fail 'Universe-only source should not duplicate main when main is already configured'
if grep -Fq 'Components: main universe' "$ubuntu_source"; then fail 'Existing main component was unnecessarily duplicated'; fi
sp_apt_bootstrap_rollback
pass 'Ubuntu bootstrap adds only Universe when official main is already configured'

printf 'APT repository bootstrap assertions: all passed\n'
