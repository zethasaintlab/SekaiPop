#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
PASS=0
FAIL=0
pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
contains() { grep -Fq -- "$2" "$1"; }
not_contains() { ! grep -RFq -- "$2" "$1"; }
for script in "$ROOT"/install.sh "$ROOT"/install-deps.sh "$ROOT"/check-deps.sh "$ROOT"/install-multi.sh "$ROOT"/tests/test-hyprland-autostart.sh; do
    if bash -n "$script"; then pass "Bash syntax: $(basename "$script")"; else fail "Bash syntax: $(basename "$script")"; fi
done
if env SEKAIPOP_INSTALLER_ROOT="$ROOT" "$ROOT/install.sh" --help >/dev/null; then pass 'Help works without distro detection'; else fail 'Help works without distro detection'; fi
if env SEKAIPOP_INSTALLER_ROOT="$ROOT" "$ROOT/install.sh" --version >/dev/null; then pass 'Version works without distro detection'; else fail 'Version works without distro detection'; fi
contains "$ROOT/installer/core/detect.sh" 'arch|endeavouros|cachyos' && pass 'Arch-family IDs are explicitly allowlisted' || fail 'Arch-family IDs are explicitly allowlisted'
contains "$ROOT/installer/core/detect.sh" 'fedora)' && pass 'Fedora ID has an explicit backend route' || fail 'Fedora ID has an explicit backend route'
contains "$ROOT/installer/core/detect.sh" 'debian)' && pass 'Debian ID has an explicit backend route' || fail 'Debian ID has an explicit backend route'
contains "$ROOT/installer/core/detect.sh" 'ubuntu)' && pass 'Ubuntu ID has an explicit backend route' || fail 'Ubuntu ID has an explicit backend route'
contains "$ROOT/installer/core/detect.sh" 'ID_LIKE is informational only' && pass 'ID_LIKE never triggers implicit fallback' || fail 'ID_LIKE never triggers implicit fallback'
contains "$ROOT/installer/core/detect.sh" 'silverblue|kinoite|sericea|onyx|sway-atomic|budgie-atomic' && pass 'Fedora Atomic variants are rejected' || fail 'Fedora Atomic variants are rejected'
not_contains "$ROOT/installer/core/detect.sh" 'opensuse)' && pass 'openSUSE is not in the supported ID allowlist' || fail 'openSUSE is not in the supported ID allowlist'
contains "$ROOT/installer/core/plan.sh" '6.12.0' && pass 'Qt 6.12 shader baseline is encoded in planning' || fail 'Qt 6.12 shader baseline is encoded in planning'
contains "$ROOT/installer/core/plan.sh" 'quickshell) sp_have qs ;;' && pass 'Quickshell runtime detection uses the actual qs executable' || fail 'Quickshell runtime detection uses the actual qs executable'
contains "$ROOT/installer/core/plan.sh" 'ffmpeg) sp_have ffmpeg ;;' && pass 'FFmpeg runtime detection accepts an existing ffmpeg executable' || fail 'FFmpeg runtime detection accepts an existing ffmpeg executable'
contains "$ROOT/installer/distros/fedora/packages.sh" "[qt6-base]='qt6-qtbase'" && pass 'Fedora Qt runtime map excludes development headers' || fail 'Fedora Qt runtime map excludes development headers'
not_contains "$ROOT/installer/distros/fedora/packages.sh" 'qt6-qtbase-devel' && pass 'Fedora Qt runtime map does not install qtbase development files' || fail 'Fedora Qt runtime map does not install qtbase development files'
contains "$ROOT/installer/core/plan.sh" 'tuned-ppd.service' && pass 'Fedora tuned-ppd compatibility provider is recognized' || fail 'Fedora tuned-ppd compatibility provider is recognized'
contains "$ROOT/installer/core/plan.sh" 'NameHasOwner' && pass 'Fedora TuneD provider verifies D-Bus name ownership' || fail 'Fedora TuneD provider verifies D-Bus name ownership'
contains "$ROOT/installer/core/plan.sh" '/org/freedesktop/UPower/PowerProfiles' && pass 'Fedora TuneD provider verifies the PowerProfiles API object' || fail 'Fedora TuneD provider verifies the PowerProfiles API object'
contains "$ROOT/installer/catalog/requirements.sh" 'qt6-shadertools' && pass 'Shader Tools has a documented logical capability' || fail 'Shader Tools has a documented logical capability'
contains "$ROOT/installer/integrations/hyprland.sh" '0.55.0' && pass 'Hyprland Lua minimum version is checked' || fail 'Hyprland Lua minimum version is checked'
contains "$ROOT/installer/integrations/hyprland.sh" 'sp_hyprland_has_quickshell_autostart' && pass 'Hyprland startup detection uses mode-specific active config sources' || fail 'Hyprland startup detection uses mode-specific active config sources'
not_contains "$ROOT/installer/integrations/hyprland.sh" 'grep -rqsE --exclude=' && pass 'Hyprland startup detection does not recursively scan documentation and unrelated configs' || fail 'Hyprland startup detection does not recursively scan documentation and unrelated configs'
contains "$ROOT/installer/integrations/quickshell.sh" 'Quickshell/Services/SystemTray' && pass 'Quickshell QML modules are checked' || fail 'Quickshell QML modules are checked'
contains "$ROOT/installer/package-managers/pacman.sh" 'pacman -Syu' && pass 'Arch full upgrade path is explicit' || fail 'Arch full upgrade path is explicit'
contains "$ROOT/installer/package-managers/apt.sh" 'apt-cache -t' && pass 'APT package-specific suite targets are supported' || fail 'APT package-specific suite targets are supported'
contains "$ROOT/installer/package-managers/dnf5.sh" 'repoquery' && pass 'DNF5 resolves package candidates natively' || fail 'DNF5 resolves package candidates natively'
contains "$ROOT/installer/core/backup.sh" 'quickshell_exists' && pass 'Backup manifest tracks original path existence' || fail 'Backup manifest tracks original path existence'
contains "$ROOT/installer/core/deployment.sh" 'qs kill -p' && pass 'Quickshell restart is scoped to its config path' || fail 'Quickshell restart is scoped to its config path'
not_contains "$ROOT/installer/core/deployment.sh" 'pkill -f qs' && pass 'No global Quickshell process kill' || fail 'No global Quickshell process kill'
not_contains "$ROOT/installer" 'curl -fsSL' && pass 'Installer does not pipe remote code to Bash' || fail 'Installer does not pipe remote code to Bash'
for legacy in install-fedora.sh install-deps-fedora.sh check-deps-fedora.sh; do
    [[ ! -e "$ROOT/$legacy" ]] && pass "Legacy root wrapper absent: $legacy" || fail "Legacy root wrapper must be absent: $legacy"
done
if bash "$ROOT/tests/test-hyprland-autostart.sh"; then pass 'Hyprland autostart regression fixtures'; else fail 'Hyprland autostart regression fixtures'; fi
printf '\nSmoke assertions: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
