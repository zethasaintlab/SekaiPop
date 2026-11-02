#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
PASS=0
FAIL=0
pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
contains() { grep -Fq -- "$2" "$1"; }
not_contains() { ! grep -RFq -- "$2" "$1"; }
for script in "$ROOT"/install.sh "$ROOT"/install-deps.sh "$ROOT"/check-deps.sh "$ROOT"/install-multi.sh "$ROOT"/tests/test-hyprland-autostart.sh "$ROOT"/tests/test-kali-routing.sh "$ROOT"/tests/test-fedora-power-provider.sh "$ROOT"/tests/test-deployment-transaction.sh; do
    if bash -n "$script"; then pass "Bash syntax: $(basename "$script")"; else fail "Bash syntax: $(basename "$script")"; fi
done
if env SEKAIPOP_INSTALLER_ROOT="$ROOT" "$ROOT/install.sh" --help >/dev/null; then pass 'Help works without distro detection'; else fail 'Help works without distro detection'; fi
if env SEKAIPOP_INSTALLER_ROOT="$ROOT" "$ROOT/install.sh" --version >/dev/null; then pass 'Version works without distro detection'; else fail 'Version works without distro detection'; fi
contains "$ROOT/installer/core/detect.sh" 'arch|endeavouros|cachyos' && pass 'Arch-family IDs are explicitly allowlisted' || fail 'Arch-family IDs are explicitly allowlisted'
contains "$ROOT/installer/core/detect.sh" 'fedora)' && pass 'Fedora ID has an explicit backend route' || fail 'Fedora ID has an explicit backend route'
contains "$ROOT/installer/core/detect.sh" 'debian)' && pass 'Debian ID has an explicit backend route' || fail 'Debian ID has an explicit backend route'
contains "$ROOT/installer/core/detect.sh" 'ubuntu)' && pass 'Ubuntu ID has an explicit backend route' || fail 'Ubuntu ID has an explicit backend route'
contains "$ROOT/installer/core/detect.sh" 'kali) SP_BACKEND=apt; SP_PROFILE_ID=kali ;;' && pass 'Kali has a dedicated APT profile route' || fail 'Kali has a dedicated APT profile route'
contains "$ROOT/installer/core/detect.sh" 'kali:*:kali-rolling' && pass 'Kali release gate requires kali-rolling' || fail 'Kali release gate requires kali-rolling'
contains "$ROOT/installer/distros/kali/packages.sh" 'quickshell/kali-rolling' && pass 'Kali Quickshell package is pinned to kali-rolling' || fail 'Kali Quickshell package is pinned to kali-rolling'
contains "$ROOT/installer/distros/kali/packages.sh" 'hyprland/kali-rolling' && pass 'Kali Hyprland package is pinned to kali-rolling' || fail 'Kali Hyprland package is pinned to kali-rolling'
contains "$ROOT/installer/distros/debian/packages.sh" "[qt6-svg]='qt6-svg-plugins'" && pass 'Debian maps Qt SVG to the runtime image plugin package' || fail 'Debian maps Qt SVG to the runtime image plugin package'
contains "$ROOT/installer/distros/ubuntu/packages.sh" "[qt6-svg]='qt6-svg-plugins'" && pass 'Ubuntu maps Qt SVG to the runtime image plugin package' || fail 'Ubuntu maps Qt SVG to the runtime image plugin package'
contains "$ROOT/installer/distros/kali/packages.sh" "[qt6-svg]='qt6-svg-plugins/kali-rolling'" && pass 'Kali maps Qt SVG to the runtime image plugin package' || fail 'Kali maps Qt SVG to the runtime image plugin package'
contains "$ROOT/installer/catalog/requirements.sh" 'jetbrains-mono' && pass 'Font capability is named for the actual JetBrains Mono package' || fail 'Font capability is named for the actual JetBrains Mono package'
not_contains "$ROOT/installer/catalog/requirements.sh" 'nerd-font' && pass 'Installer does not mislabel plain JetBrains Mono as a Nerd Font' || fail 'Installer does not mislabel plain JetBrains Mono as a Nerd Font'
contains "$ROOT/installer/distros/fedora/packages.sh" "[jetbrains-mono]='jetbrains-mono-fonts'" && pass 'Fedora maps JetBrains Mono to the matching package' || fail 'Fedora maps JetBrains Mono to the matching package'
contains "$ROOT/installer/distros/debian/packages.sh" "[jetbrains-mono]='fonts-jetbrains-mono'" && pass 'Debian maps JetBrains Mono to the matching package' || fail 'Debian maps JetBrains Mono to the matching package'
contains "$ROOT/installer/distros/ubuntu/packages.sh" "[jetbrains-mono]='fonts-jetbrains-mono'" && pass 'Ubuntu maps JetBrains Mono to the matching package' || fail 'Ubuntu maps JetBrains Mono to the matching package'
contains "$ROOT/installer/distros/kali/packages.sh" "[jetbrains-mono]='fonts-jetbrains-mono/kali-rolling'" && pass 'Kali maps JetBrains Mono to the matching package' || fail 'Kali maps JetBrains Mono to the matching package'
not_contains "$ROOT/installer/distros/kali/packages.sh" 'trixie-backports' && pass 'Kali package profile does not inherit Debian backports' || fail 'Kali package profile does not inherit Debian backports'
contains "$ROOT/installer/core/plan.sh" 'sp_kali_apt_sources_are_safe' && pass 'Kali APT source policy is implemented' || fail 'Kali APT source policy is implemented'
contains "$ROOT/installer/core/plan.sh" 'sp_fedora_tuned_ppd_installed' && pass 'Fedora TuneD PPD provider is recognized even when inactive' || fail 'Fedora TuneD PPD provider is recognized even when inactive'
contains "$ROOT/installer/integrations/systemd.sh" 'tuned-ppd.service' && pass 'Fedora TuneD PPD service is reconciled without adding a second provider' || fail 'Fedora TuneD PPD service is reconciled without adding a second provider'
contains "$ROOT/installer/core/plan.sh" 'sp_fedora_tlp_pd_installed' && pass 'Fedora TLP profile daemon provider is recognized' || fail 'Fedora TLP profile daemon provider is recognized'
contains "$ROOT/installer/core/plan.sh" 'TLP is installed without tlp-pd' && pass 'Fedora TLP-only conflict is reported instead of installing another provider' || fail 'Fedora TLP-only conflict is reported instead of installing another provider'
contains "$ROOT/installer/integrations/systemd.sh" 'tlp-pd.service' && pass 'Fedora TLP profile service is reconciled when installed' || fail 'Fedora TLP profile service is reconciled when installed'
contains "$ROOT/installer/core/deployment.sh" 'sp_prepare_shaders "$stage/shaders"' && pass 'Shaders are prepared in staging before Quickshell replacement' || fail 'Shaders are prepared in staging before Quickshell replacement'
contains "$ROOT/installer/core/main.sh" 'sp_rollback_failed_deployment' && pass 'Failed deployment phases have automatic configuration rollback' || fail 'Failed deployment phases have automatic configuration rollback'
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
contains "$ROOT/installer/integrations/hyprland.sh" 'sp_hyprland_lua_qs_alias_targets_sekaipop' && pass 'Hyprland startup detection recognizes the upstream QS variable alias' || fail 'Hyprland startup detection recognizes the upstream QS variable alias'
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
if bash "$ROOT/tests/test-kali-routing.sh"; then pass 'Kali routing and repository policy fixtures'; else fail 'Kali routing and repository policy fixtures'; fi
if bash "$ROOT/tests/test-fedora-power-provider.sh"; then pass 'Fedora power-provider regression fixtures'; else fail 'Fedora power-provider regression fixtures'; fi
if bash "$ROOT/tests/test-deployment-transaction.sh"; then pass 'Deployment staging and rollback regression fixtures'; else fail 'Deployment staging and rollback regression fixtures'; fi
printf '\nSmoke assertions: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
