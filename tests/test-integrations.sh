#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-integration.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
export SEKAIPOP_INSTALLER_ROOT="$ROOT" HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
mkdir -p "$XDG_CONFIG_HOME/hypr" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
cat > "$TMP/bin/Hyprland" <<'MOCK'
#!/usr/bin/env bash
printf 'Hyprland 0.56.2\n'
MOCK
chmod +x "$TMP/bin/Hyprland"
source "$ROOT/installer/core/main.sh"
SP_HYPR_DEST="$XDG_CONFIG_HOME/hypr"
SP_QS_DEST="$XDG_CONFIG_HOME/quickshell/sekaipop"
SP_HYPR=merge SP_TIMESTAMP=integration-test SP_YES=1
printf 'bind = SUPER, Return, exec, kitty\n' > "$SP_HYPR_DEST/hyprland.conf"
sp_integrate_hyprland "$ROOT/hypr"
sp_integrate_hyprland "$ROOT/hypr"
grep -Fq 'bind = SUPER, Return, exec, kitty' "$SP_HYPR_DEST/hyprland.conf"
grep -Fq "source = $SP_HYPR_DEST/sekaipop_session.conf" "$SP_HYPR_DEST/hyprland.conf"
[[ "$(grep -Fc "source = $SP_HYPR_DEST/sekaipop_session.conf" "$SP_HYPR_DEST/hyprland.conf")" == 1 ]]
grep -Fq 'qs -c sekaipop' "$SP_HYPR_DEST/sekaipop_session.conf"
printf '[PASS] Hyprland merge preserves user config and is idempotent\n'
printf '\n# user-owned customization\n' >> "$SP_HYPR_DEST/sekaipop_session.conf"
sp_integrate_hyprland "$ROOT/hypr" || true
grep -Fq 'user-owned customization' "$SP_HYPR_DEST/sekaipop_session.conf"
compgen -G "$SP_HYPR_DEST/sekaipop_session.conf.proposed.*" >/dev/null
printf '[PASS] User-edited session hook is preserved and a proposal is staged\n'
HYPR_CONFIG_BEFORE="$(cat "$SP_HYPR_DEST/hyprland.conf")"
cat > "$TMP/bin/Hyprland" <<'MOCK'
#!/usr/bin/env bash
printf 'Hyprland 0.54.0\n'
MOCK
if (sp_integrate_hyprland "$ROOT/hypr") >/dev/null 2>&1; then
    printf '[FAIL] Hyprland below 0.55 was accepted\n' >&2
    exit 1
fi
[[ "$(cat "$SP_HYPR_DEST/hyprland.conf")" == "$HYPR_CONFIG_BEFORE" ]]
printf '[PASS] Incompatible Hyprland is rejected before config modification\n'
printf 'outside-content\n' > "$TMP/outside"
ln -s "$TMP/outside" "$TMP/symlink.conf"
if (sp_atomic_append_once "$TMP/symlink.conf" 'injected = true') >/dev/null 2>&1; then
    printf '[FAIL] Symlink configuration target was accepted\n' >&2
    exit 1
fi
[[ "$(cat "$TMP/outside")" == outside-content ]]
printf '[PASS] Configuration append refuses symlink targets\n'
