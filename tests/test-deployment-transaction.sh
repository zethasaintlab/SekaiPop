#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-deploy-transaction.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

export SEKAIPOP_INSTALLER_ROOT="$ROOT"
source "$ROOT/installer/core/main.sh"

pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }

SOURCE="$TMP/source"
PARENT="$TMP/home/.config/quickshell"
SP_QS_DEST="$PARENT/sekaipop"
SP_TIMESTAMP=20261102180000
SP_WITH_TESTS=0
SP_DRY_RUN=0
mkdir -p "$SOURCE/shaders" "$PARENT" "$SP_QS_DEST"
printf 'new-shell\n' > "$SOURCE/shell.qml"
printf 'void main() {}\n' > "$SOURCE/shaders/staged.vert"
printf '#!/usr/bin/env bash\nexit 0\n' > "$SOURCE/shaders/compile-shaders.sh"
printf 'old-install\n' > "$SP_QS_DEST/previous-install.marker"
printf 'preserved-user-data\n' > "$SP_QS_DEST/settings.json"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/qtpaths6" <<'QT'
#!/usr/bin/env bash
printf '6.11.2\n'
QT
chmod +x "$TMP/bin/qtpaths6"
PATH="$TMP/bin:/usr/bin:/bin"
export PATH
sp_find_qsb() { return 1; }

if (sp_deploy_quickshell "$SOURCE") > "$TMP/staging-failure.log" 2>&1; then
    fail 'Staged shader failure must abort Quickshell replacement'
fi
[[ -f "$SP_QS_DEST/previous-install.marker" ]] || fail 'Existing Quickshell tree remains intact after staged shader failure'
[[ "$(cat "$SP_QS_DEST/previous-install.marker")" == old-install ]] || fail 'Existing Quickshell marker content is unchanged'
[[ "$(cat "$SP_QS_DEST/settings.json")" == preserved-user-data ]] || fail 'Existing user settings remain untouched after staged shader failure'
[[ ! -e "$SP_QS_DEST/shell.qml" ]] || fail 'New shell tree was not installed after staged shader failure'
if find "$PARENT" -maxdepth 1 -type d -name '.sekaipop-stage.*' -print -quit | grep -q .; then
    fail 'Failed staging directory is cleaned up'
fi
pass 'Shader compilation is performed before the existing Quickshell tree is replaced'

SP_CONFIG_HOME="$TMP/rollback-home/.config"
SP_STATE_DIR="$TMP/rollback-home/.local/state/sekaipop"
SP_BACKUP_ROOT="$SP_STATE_DIR/installer-backups"
SP_QS_DEST="$SP_CONFIG_HOME/quickshell/sekaipop"
SP_HYPR_DEST="$SP_CONFIG_HOME/hypr"
SP_TIMESTAMP=20261102180100
SP_DISTRO_ID=fedora
SP_DISTRO_VERSION=44
SP_BACKEND=dnf5
SP_PROFILE=standard
SP_HYPR=merge
SP_YES=0
mkdir -p "$SP_QS_DEST" "$SP_HYPR_DEST"
printf 'previous-shell\n' > "$SP_QS_DEST/original.marker"
printf 'previous-hypr\n' > "$SP_HYPR_DEST/original.marker"
sp_create_backup 1 1
FIRST_BACKUP="$SP_BACKUP_DIR"
printf 'intervening-state\n' > "$SP_QS_DEST/intervening.marker"
SP_TIMESTAMP=20261102180101
sp_create_backup 1 1
[[ "$SP_BACKUP_DIR" != "$FIRST_BACKUP" ]] || fail 'A changed configuration produces a distinct later snapshot'
SP_BACKUP_DIR="$FIRST_BACKUP"
printf 'partially-deployed-shell\n' > "$SP_QS_DEST/partial.marker"
printf 'partially-integrated-hypr\n' > "$SP_HYPR_DEST/partial.marker"

if (sp_rollback_failed_deployment 'Simulated integration failure.') > "$TMP/rollback.log" 2>&1; then
    fail 'Failed deployment rollback reports a non-zero deployment result'
fi
[[ "$(cat "$SP_QS_DEST/original.marker")" == previous-shell ]] || fail 'Automatic rollback restores the previous Quickshell tree'
[[ ! -e "$SP_QS_DEST/partial.marker" ]] || fail 'Automatic rollback removes the partial Quickshell tree'
[[ ! -e "$SP_QS_DEST/intervening.marker" ]] || fail 'Automatic rollback restores the exact snapshot created for the current transaction'
[[ "$(cat "$SP_HYPR_DEST/original.marker")" == previous-hypr ]] || fail 'Automatic rollback restores the previous Hyprland tree'
[[ ! -e "$SP_HYPR_DEST/partial.marker" ]] || fail 'Automatic rollback removes partial Hyprland integration'
find "$SP_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'restore-*' -print -quit | grep -q . || fail 'Automatic rollback retains a recovery snapshot of the partial state'
pass 'Failed Hyprland integration automatically restores both configuration trees and preserves recovery data'

ACT_HOME="$TMP/activation-home"
SP_CONFIG_HOME="$ACT_HOME/.config"
SP_STATE_DIR="$ACT_HOME/.local/state/sekaipop"
SP_BACKUP_ROOT="$SP_STATE_DIR/installer-backups"
SP_QS_DEST="$SP_CONFIG_HOME/quickshell/sekaipop"
SP_HYPR_DEST="$SP_CONFIG_HOME/hypr"
SP_TIMESTAMP=20261102180200
SP_HYPR=skip
SP_YES=0
SP_DRY_RUN=0
mkdir -p "$SP_QS_DEST"
printf 'activation-previous\n' > "$SP_QS_DEST/original.marker"
sp_find_rice_source() { :; }
sp_deploy_quickshell() {
    rm -rf -- "$SP_QS_DEST"
    mkdir -p "$SP_QS_DEST"
    printf 'activation-partial\n' > "$SP_QS_DEST/partial.marker"
}
sp_check_all() { return 0; }
sp_setup_services() { return 0; }
sp_activate_sekaipop() { return 1; }

if (sp_deploy_application) > "$TMP/activation-failure.log" 2>&1; then
    fail 'Quickshell activation failure must fail the deployment transaction'
fi
[[ "$(cat "$SP_QS_DEST/original.marker")" == activation-previous ]] || fail 'Activation failure restores the previous Quickshell tree'
[[ ! -e "$SP_QS_DEST/partial.marker" ]] || fail 'Activation failure removes the partially deployed tree'
[[ ! -e "$SP_STATE_DIR/installer-manifest.env" ]] || fail 'Failed activation must not write a successful installer manifest'
pass 'Quickshell activation failure triggers configuration rollback before success is recorded'

printf '\nDeployment transaction fixtures passed.\n'

# A permission-only configuration change must not reuse a stale snapshot.
META_HOME="$TMP/metadata-home"
SP_CONFIG_HOME="$META_HOME/.config"
SP_STATE_DIR="$META_HOME/.local/state/sekaipop"
SP_BACKUP_ROOT="$SP_STATE_DIR/installer-backups"
SP_QS_DEST="$SP_CONFIG_HOME/quickshell/sekaipop"
SP_HYPR_DEST="$SP_CONFIG_HOME/hypr"
SP_TIMESTAMP=20261102180300
SP_DISTRO_ID=fedora
SP_DISTRO_VERSION=44
SP_BACKEND=dnf5
SP_PROFILE=standard
SP_HYPR=skip
mkdir -p "$SP_QS_DEST"
printf 'unchanged file content\n' > "$SP_QS_DEST/mode-only.marker"
chmod 0644 "$SP_QS_DEST/mode-only.marker"
sp_create_backup 1 0
MODE_BACKUP="$SP_BACKUP_DIR"
[[ "$(stat -c '%a' "$MODE_BACKUP/config/sekaipop/mode-only.marker")" == 644 ]] ||
    fail 'Initial snapshot retains the original file mode'
chmod 0600 "$SP_QS_DEST/mode-only.marker"
SP_TIMESTAMP=20261102180301
sp_create_backup 1 0
[[ "$SP_BACKUP_DIR" != "$MODE_BACKUP" ]] ||
    fail 'A permission-only change must create a fresh pre-transaction snapshot'
[[ "$(stat -c '%a' "$SP_BACKUP_DIR/config/sekaipop/mode-only.marker")" == 600 ]] ||
    fail 'Fresh snapshot records the current private file permission'
pass 'Snapshot reuse checks filesystem metadata, not only file contents'

# Installer state must be replaced atomically and retain the old manifest on a failed rename.
MANIFEST_HOME="$TMP/manifest-home"
SP_STATE_DIR="$MANIFEST_HOME/.local/state/sekaipop"
SP_DRY_RUN=0
SP_DISTRO_ID=fedora
SP_DISTRO_VERSION=44
SP_BACKEND=dnf5
SP_PROFILE=standard
SP_HYPR=merge
SP_INSTALL_PKGS=(quickshell hyprland)
SP_BACKUP_DIR="$TMP/manifest-backup"
mkdir -p "$SP_STATE_DIR"
printf 'previous-successful-manifest\n' > "$SP_STATE_DIR/installer-manifest.env"
sp_write_state_manifest
grep -Fq 'installer_version=2.1.0' "$SP_STATE_DIR/installer-manifest.env" || fail 'Successful manifest replacement writes the current installer version'
[[ "$(stat -c '%a' "$SP_STATE_DIR/installer-manifest.env")" == 600 ]] || fail 'Installer manifest is private to the user'
if compgen -G "$SP_STATE_DIR/.installer-manifest.*" >/dev/null; then
    fail 'Successful atomic manifest write leaves no temporary files'
fi
printf 'prior-manifest-must-survive\n' > "$SP_STATE_DIR/installer-manifest.env"
if (
    mv() {
        if [[ "${!#}" == "$SP_STATE_DIR/installer-manifest.env" ]]; then return 1; fi
        command mv "$@"
    }
    sp_write_state_manifest
) >/dev/null 2>&1; then
    fail 'A failed manifest activation must be reported'
fi
[[ "$(cat "$SP_STATE_DIR/installer-manifest.env")" == prior-manifest-must-survive ]] ||
    fail 'A failed atomic manifest replacement leaves the previous successful manifest intact'
if compgen -G "$SP_STATE_DIR/.installer-manifest.*" >/dev/null; then
    fail 'Failed atomic manifest replacement cleans up its temporary file'
fi
pass 'Installer state manifest is atomically replaced and preserves the prior manifest on failure'

printf '\nAtomic manifest fixtures passed.\n'

# Dependency-only mode with --hypr skip has no config snapshot. Its rollback
# must restore service state without pretending that config restoration failed.
NO_CONFIG_ROLLBACK="$TMP/deps-only-rollback.log"
SP_BACKUP_DIR=''
sp_service_transaction_rollback() {
    printf 'service-rollback\n' >> "$NO_CONFIG_ROLLBACK"
    return 0
}
sp_die() {
    printf 'die:%s\n' "$1" >> "$NO_CONFIG_ROLLBACK"
    return 1
}
: > "$NO_CONFIG_ROLLBACK"
if sp_rollback_failed_dependency_only 'Simulated deps-only service failure'; then
    fail 'Dependency-only rollback must preserve its non-zero failure result'
fi
grep -Fxq -- service-rollback "$NO_CONFIG_ROLLBACK" ||
    fail 'Dependency-only rollback reverts service changes without a config snapshot'
grep -Fq -- 'No Quickshell/Hyprland configuration was modified; service changes were reverted.' "$NO_CONFIG_ROLLBACK" ||
    fail 'Dependency-only rollback reports that no configuration restore was required'
pass 'Dependency-only --hypr skip rollback handles service changes without requiring a configuration snapshot'

sp_service_transaction_rollback() { return 1; }
: > "$NO_CONFIG_ROLLBACK"
if sp_rollback_failed_dependency_only 'Simulated deps-only service rollback failure'; then
    fail 'Dependency-only service rollback failure must be reported'
fi
grep -Fq -- 'one or more system/user service states could not be reverted' "$NO_CONFIG_ROLLBACK" ||
    fail 'Dependency-only rollback exposes incomplete systemd recovery'
pass 'Dependency-only rollback reports service-state recovery failures explicitly'

printf '\nDependency-only transaction fixtures passed.\n'

# A restore must not modify either destination unless both current trees have
# first been copied successfully into the recovery snapshot.
RESTORE_HOME="$TMP/restore-copy-failure"
SP_CONFIG_HOME="$RESTORE_HOME/.config"
SP_STATE_DIR="$RESTORE_HOME/.local/state/sekaipop"
SP_BACKUP_ROOT="$SP_STATE_DIR/installer-backups"
SP_QS_DEST="$SP_CONFIG_HOME/quickshell/sekaipop"
SP_HYPR_DEST="$SP_CONFIG_HOME/hypr"
SP_TIMESTAMP=20261102180400
mkdir -p "$SP_BACKUP_ROOT/source/config/sekaipop" "$SP_BACKUP_ROOT/source/config/hypr" "$SP_QS_DEST" "$SP_HYPR_DEST"
printf 'snapshot-shell\n' > "$SP_BACKUP_ROOT/source/config/sekaipop/original.marker"
printf 'snapshot-hypr\n' > "$SP_BACKUP_ROOT/source/config/hypr/original.marker"
cat > "$SP_BACKUP_ROOT/source/manifest" <<'MANIFEST'
quickshell_included=yes
hyprland_included=yes
quickshell_exists=yes
hyprland_exists=yes
MANIFEST
printf 'current-shell\n' > "$SP_QS_DEST/current.marker"
printf 'current-hypr\n' > "$SP_HYPR_DEST/current.marker"
if (
    cp() {
        if [[ "${3:-}" == "$SP_QS_DEST" ]]; then return 42; fi
        command /usr/bin/cp "$@"
    }
    sp_confirm() { return 0; }
    sp_restore_latest "$SP_BACKUP_ROOT/source"
) > "$TMP/restore-copy-failure.log" 2>&1; then
    fail 'A failed recovery snapshot copy must abort restore'
fi
[[ "$(cat "$SP_QS_DEST/current.marker")" == current-shell ]] || fail 'Quickshell destination remains unchanged when its recovery copy fails'
[[ "$(cat "$SP_HYPR_DEST/current.marker")" == current-hypr ]] || fail 'Hyprland destination remains unchanged when its recovery copy fails'
grep -Fq 'nothing was restored' "$TMP/restore-copy-failure.log" || fail 'Recovery-copy failure explains that restore did not begin'
pass 'Restore aborts before changing user configuration when the recovery snapshot cannot be completed'

# A malformed explicit snapshot must fail closed rather than silently restore nothing.
mkdir -p "$SP_BACKUP_ROOT/malformed"
if ( sp_confirm() { return 0; }; sp_restore_latest "$SP_BACKUP_ROOT/malformed" ) > "$TMP/malformed-snapshot.log" 2>&1; then
    fail 'An explicit snapshot without a manifest must be rejected'
fi
[[ "$(cat "$SP_QS_DEST/current.marker")" == current-shell ]] || fail 'Malformed snapshot cannot modify the current Quickshell tree'
pass 'Explicit snapshots with missing manifests are rejected without touching user configuration'
