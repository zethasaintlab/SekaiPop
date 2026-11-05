#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-touchpad-key.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/config/hypr"
export XDG_CONFIG_HOME="$TMP/config"
export HYPRCTL_LOG="$TMP/hyprctl.log"
cat > "$TMP/bin/hyprctl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HYPRCTL_LOG"
case "$1" in
    eval) printf 'ok\n' ;;
    getoption) printf 'int: 1\n' ;;
esac
MOCK
chmod +x "$TMP/bin/hyprctl"
export PATH="$TMP/bin:/usr/bin:/bin"
SCRIPT="$ROOT/sekaipop/scripts/hyprland/hyprland-settings.sh"
touch "$TMP/config/hypr/hyprland.lua"

"$SCRIPT" set input.touchpad.tap-to-click bool true
grep -Fq 'hl.config({ ["input"] = { ["touchpad"] = { ["tap_to_click"] = true } } }) -- sekaipop:hypr:input.touchpad.tap-to-click' "$TMP/config/hypr/sekaipop_overrides.lua" || {
    printf '[FAIL] Panel tap-to-click key must map to the Lua underscore key\n' >&2
    exit 1
}
printf '[PASS] Panel tap-to-click maps to the Hyprland Lua tap_to_click key\n'

printf 'hl.config({ ["input"] = { ["touchpad"] = { ["tap_to_click"] = false } } }) -- sekaipop:hypr:input.touchpad.tap_to_click\n' >> "$TMP/config/hypr/sekaipop_overrides.lua"
"$SCRIPT" reset input.touchpad.tap-to-click
if grep -Fq 'sekaipop:hypr:input.touchpad.tap' "$TMP/config/hypr/sekaipop_overrides.lua"; then
    printf '[FAIL] Reset must remove both legacy and Lua marker spellings\n' >&2
    exit 1
fi
printf '[PASS] Reset removes stale overrides under both key spellings\n'

"$SCRIPT" read input.touchpad.tap-to-click >/dev/null
grep -Fq 'getoption input:touchpad:tap_to_click' "$HYPRCTL_LOG" || {
    printf '[FAIL] Read must query the Lua underscore key\n' >&2
    exit 1
}
printf '[PASS] Read queries the Lua underscore key while preserving the panel key\n'

printf '\nHyprland tap-to-click fixtures passed.\n'
