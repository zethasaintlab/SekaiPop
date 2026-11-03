#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d /tmp/sekaipop-hypr-autostart.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT

export SEKAIPOP_INSTALLER_ROOT="$ROOT"
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

LUA="$TMP/lua"
mkdir -p "$LUA/hyprland" "$LUA/custom"
cat > "$LUA/hyprland.lua" <<'LUA'
load("hyprland.variables")
load("custom.variables", true)
load("hyprland.execs")
load("custom.execs", true)
LUA
cat > "$LUA/hyprland/execs.lua" <<'LUA'
-- qs -c sekaipop is only a comment and must not count.
LUA
cat > "$LUA/custom/execs.lua" <<'LUA'
-- no custom autostart
LUA
cat > "$LUA/README.md" <<'DOC'
Run qs -c sekaipop to start the shell.
DOC
cat > "$LUA/hypridle.conf" <<'CONF'
$lock_cmd = qs -c sekaipop ipc call lock lock
CONF
cat > "$LUA/sekaipop-session.conf" <<'CONF'
exec-once = qs -c sekaipop
CONF

assert_false 'Lua mode ignores README, hypridle IPC commands, unreferenced conf files, and Lua comments' \
    sp_hyprland_has_quickshell_autostart lua "$LUA"

sp_write_session_file lua "$LUA"
if grep -Fq 'hl.exec_cmd("qs -c sekaipop")' "$LUA/sekaipop_session.lua"; then
    pass 'Lua session proposal retains Quickshell startup when no loaded startup module provides it'
else
    fail 'Lua session proposal retains Quickshell startup when no loaded startup module provides it'
fi

cat >> "$LUA/hyprland/execs.lua" <<'LUA'
hl.exec_cmd("qs -c sekaipop")
LUA
assert_true 'Lua mode recognizes an active command in the loaded hyprland.execs module' \
    sp_hyprland_has_quickshell_autostart lua "$LUA"

cat > "$LUA/hyprland/variables.lua" <<'LUA'
qsConfig = "sekaipop"
QS = "qs -c " .. qsConfig
LUA
cat > "$LUA/hyprland/execs.lua" <<'LUA'
hl.exec_cmd(QS)
LUA
assert_true 'Lua mode recognizes the upstream QS variable alias used by hyprland.execs' \
    sp_hyprland_has_quickshell_autostart lua "$LUA"

cat > "$LUA/custom/variables.lua" <<'LUA'
QS = "qs -c another-shell"
LUA
assert_false 'Lua mode does not treat a custom QS override for another shell as SekaiPop autostart' \
    sp_hyprland_has_quickshell_autostart lua "$LUA"

cat > "$LUA/custom/variables.lua" <<'LUA'
QS = "qs -c sekaipop"
LUA
assert_true 'Lua mode recognizes a custom QS override targeting SekaiPop' \
    sp_hyprland_has_quickshell_autostart lua "$LUA"

CONF="$TMP/conf"
mkdir -p "$CONF/hyprland" "$CONF/custom"
cat > "$CONF/hyprland.conf" <<'CONF'
source = ./hyprland/*.conf
source = ./custom/*.conf
CONF
cat > "$CONF/hyprland/execs.conf" <<'CONF'
# exec-once = qs -c sekaipop
exec = qs -c sekaipop ipc call lock lock
CONF
cat > "$CONF/custom/execs.conf" <<'CONF'
# no startup command
CONF
cat > "$CONF/README.md" <<'DOC'
exec-once = qs -c sekaipop
DOC
cat > "$CONF/hypridle.conf" <<'CONF'
$lock_cmd = qs -c sekaipop ipc call lock lock
CONF
cat > "$CONF/sekaipop-session.conf" <<'CONF'
exec-once = qs -c sekaipop
CONF

assert_false 'Conf mode ignores documentation, hypridle IPC commands, unreferenced session files, and comments' \
    sp_hyprland_has_quickshell_autostart conf "$CONF"

cat > "$CONF/hyprland/startup.conf" <<'CONF'
# exec-once = qs -c sekaipop
exec = qs -c sekaipop ipc call lock lock
CONF
assert_false 'Conf mode ignores non-startup IPC commands in other sourced files' \
    sp_hyprland_has_quickshell_autostart conf "$CONF"

cat >> "$CONF/hyprland/startup.conf" <<'CONF'
exec-once = qs -c sekaipop
CONF
assert_true 'Conf mode follows sourced config globs to find startup directives' \
    sp_hyprland_has_quickshell_autostart conf "$CONF"

cat >> "$CONF/hyprland/execs.conf" <<'CONF'
exec-once = qs -c sekaipop
CONF
assert_true 'Conf mode recognizes an exec-once directive in a sourced execs.conf' \
    sp_hyprland_has_quickshell_autostart conf "$CONF"

# Nested source graphs are followed relative to the file containing source=.
NESTED="$TMP/nested"
mkdir -p "$NESTED/layers" "$NESTED/nested"
cat > "$NESTED/hyprland.conf" <<'CONF'
source = ./layers/*.conf
CONF
cat > "$NESTED/layers/00-base.conf" <<'CONF'
source = ../nested/*.conf
CONF
cat > "$NESTED/nested/10-startup.conf" <<'CONF'
exec-once = qs -c sekaipop
CONF
assert_true 'Conf mode recursively follows nested source globs relative to each included file' \
    sp_hyprland_has_quickshell_autostart conf "$NESTED"

# Include cycles are deduplicated and do not recurse indefinitely.
CYCLE="$TMP/cycle"
mkdir -p "$CYCLE"
cat > "$CYCLE/hyprland.conf" <<'CONF'
source = ./cycle-a.conf
CONF
cat > "$CYCLE/cycle-a.conf" <<'CONF'
source = ./hyprland.conf
exec-once = qs -c sekaipop
CONF
assert_true 'Conf mode handles source cycles without duplicate scanning' \
    sp_hyprland_has_quickshell_autostart conf "$CYCLE"

# Dynamic source expressions cannot be safely resolved by static inspection.
# Do not append another shell startup when an unknown include could contain one.
UNCERTAIN="$TMP/uncertain"
mkdir -p "$UNCERTAIN"
cat > "$UNCERTAIN/hyprland.conf" <<'CONF'
source = $customConfigPath
CONF
assert_true 'Conf mode treats unresolved source expressions as an ambiguous autostart graph' \
    sp_hyprland_has_quickshell_autostart conf "$UNCERTAIN"
sp_write_session_file conf "$UNCERTAIN"
if grep -Fq 'qs -c sekaipop' "$UNCERTAIN/sekaipop_session.conf"; then
    fail 'An ambiguous source graph must not receive a second Quickshell startup command'
else
    pass 'An ambiguous source graph withholds automatic Quickshell startup to avoid duplicate launches'
fi
printf '\nHyprland autostart fixtures passed.\n'
