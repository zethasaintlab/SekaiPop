#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
SCRIPT="$ROOT/tools/fedora-hyprland-host-user-integration.sh"
TMP="$(mktemp -d /tmp/sekaipop-host-user-units.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home" "$TMP/prefix/lib64/systemd/user" "$TMP/prefix/lib/systemd/user"
PREFIX="$TMP/prefix"
printf '[Unit]\nDescription=Hyprland session\n' > "$PREFIX/lib64/systemd/user/hyprland-session.target"
printf '[Service]\nExecStart=/opt/sekaipop/test/portal\n' > "$PREFIX/lib/systemd/user/xdg-desktop-portal-hyprland.service"

cat > "$TMP/bin/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
[[ "$1" == --user && "$2" == daemon-reload ]] || exit 2
if [[ "${SEKAIPOP_TEST_SYSTEMCTL_FAIL:-0}" == 1 ]]; then
    exit 1
fi
exit 0
SYSTEMCTL
chmod +x "$TMP/bin/systemctl"
export PATH="$TMP/bin:$PATH"
export HOME="$TMP/home"
export SEKAIPOP_TESTING=1
export SEKAIPOP_TEST_PREFIX_ROOT="$TMP"
export XDG_CONFIG_HOME="$TMP/config"

UNIT_DIR="$XDG_CONFIG_HOME/systemd/user"
TARGET="$UNIT_DIR/hyprland-session.target"
PORTAL="$UNIT_DIR/xdg-desktop-portal-hyprland.service"

bash "$SCRIPT" install "$PREFIX" | grep -Fq 'FEDORA_HYPRLAND_USER_UNITS_INSTALLED'
[[ -L "$TARGET" && "$(readlink "$TARGET")" == "$PREFIX/lib64/systemd/user/hyprland-session.target" ]]
[[ -L "$PORTAL" && "$(readlink "$PORTAL")" == "$PREFIX/lib/systemd/user/xdg-desktop-portal-hyprland.service" ]]
bash "$SCRIPT" install "$PREFIX" >/dev/null

bash "$SCRIPT" remove "$PREFIX" | grep -Fq 'FEDORA_HYPRLAND_USER_UNITS_REMOVED'
[[ ! -e "$TARGET" && ! -L "$TARGET" ]]
[[ ! -e "$PORTAL" && ! -L "$PORTAL" ]]

CONFLICT_CONFIG="$TMP/conflict-config"
mkdir -p "$CONFLICT_CONFIG/systemd/user"
printf 'existing user unit\n' > "$CONFLICT_CONFIG/systemd/user/xdg-desktop-portal-hyprland.service"
export XDG_CONFIG_HOME="$CONFLICT_CONFIG"
if bash "$SCRIPT" install "$PREFIX" >/dev/null 2>&1; then
    echo '[FAIL] conflicting user unit was overwritten'
    exit 1
fi
[[ ! -e "$CONFLICT_CONFIG/systemd/user/hyprland-session.target" ]]
grep -Fq 'existing user unit' "$CONFLICT_CONFIG/systemd/user/xdg-desktop-portal-hyprland.service"

FAIL_CONFIG="$TMP/fail-config"
export XDG_CONFIG_HOME="$FAIL_CONFIG"
export SEKAIPOP_TEST_SYSTEMCTL_FAIL=1
if bash "$SCRIPT" install "$PREFIX" >/dev/null 2>&1; then
    echo '[FAIL] systemd daemon-reload failure was accepted'
    exit 1
fi
[[ ! -e "$FAIL_CONFIG/systemd/user/hyprland-session.target" ]]
[[ ! -e "$FAIL_CONFIG/systemd/user/xdg-desktop-portal-hyprland.service" ]]
unset SEKAIPOP_TEST_SYSTEMCTL_FAIL

REMOVE_CONFIG="$TMP/remove-config"
export XDG_CONFIG_HOME="$REMOVE_CONFIG"
bash "$SCRIPT" install "$PREFIX" >/dev/null
rm "$REMOVE_CONFIG/systemd/user/xdg-desktop-portal-hyprland.service"
ln -s "$TMP/unrelated.service" "$REMOVE_CONFIG/systemd/user/xdg-desktop-portal-hyprland.service"
if bash "$SCRIPT" remove "$PREFIX" >/dev/null 2>&1; then
    echo '[FAIL] unrelated user unit symlink was removed silently'
    exit 1
fi
[[ ! -e "$REMOVE_CONFIG/systemd/user/hyprland-session.target" ]]
[[ -L "$REMOVE_CONFIG/systemd/user/xdg-desktop-portal-hyprland.service" ]]
[[ "$(readlink "$REMOVE_CONFIG/systemd/user/xdg-desktop-portal-hyprland.service")" == "$TMP/unrelated.service" ]]

echo '[PASS] Fedora Hyprland user systemd integration is idempotent and preserves conflicting user units'
