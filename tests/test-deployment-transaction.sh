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
