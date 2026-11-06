#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
PASS=0
FAIL=0
pass() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '[FAIL] %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
contains() { grep -Fq -- "$2" "$1"; }
not_contains() { ! grep -RFq -- "$2" "$1"; }
for script in "$ROOT"/install.sh "$ROOT"/install-deps.sh "$ROOT"/check-deps.sh "$ROOT"/install-multi.sh "$ROOT"/tests/test-hyprland-autostart.sh "$ROOT"/tests/test-quickshell-activation.sh "$ROOT"/tests/test-fedora-power-provider.sh "$ROOT"/tests/test-deployment-transaction.sh "$ROOT"/tests/test-pacman-safety.sh "$ROOT"/tests/test-installer-lock.sh "$ROOT"/tests/test-shader-plan.sh "$ROOT"/tests/test-power-profile-api.sh "$ROOT"/tests/test-hyprland-touchpad-key.sh "$ROOT"/tests/test-dependency-failure-gate.sh "$ROOT"/tests/test-private-prefix-validation.sh "$ROOT"/tests/test-fedora-hyprland-source-fetch-safety.sh "$ROOT"/tests/test-fedora-hyprland-build-provenance.sh "$ROOT"/tests/test-fedora-host-provider.sh "$ROOT"/tools/fedora-hyprland-host-build.sh "$ROOT"/tools/fedora-hyprland-host-prepare-session.sh "$ROOT"/tools/fedora-hyprland-host-user-integration.sh "$ROOT"/tools/transaction-journal.sh "$ROOT"/tests/test-transaction-journal.sh "$ROOT"/tests/test-fedora-host-prepare-session.sh "$ROOT"/tests/test-fedora-host-user-integration.sh; do
    if bash -n "$script"; then pass "Bash syntax: $(basename "$script")"; else fail "Bash syntax: $(basename "$script")"; fi
done
if env SEKAIPOP_INSTALLER_ROOT="$ROOT" "$ROOT/install.sh" --help >/dev/null; then pass 'Help works without distro detection'; else fail 'Help works without distro detection'; fi
if env SEKAIPOP_INSTALLER_ROOT="$ROOT" "$ROOT/install.sh" --version >/dev/null; then pass 'Version works without distro detection'; else fail 'Version works without distro detection'; fi
contains "$ROOT/installer/core/detect.sh" 'arch|endeavouros|cachyos' && pass 'Arch-family IDs are explicitly allowlisted' || fail 'Arch-family IDs are explicitly allowlisted'
contains "$ROOT/installer/core/detect.sh" 'fedora)' && pass 'Fedora ID has an explicit backend route' || fail 'Fedora ID has an explicit backend route'
contains "$ROOT/installer/core/detect.sh" 'fedora:45:' && pass 'Fedora 45 has an exact release gate' || fail 'Fedora 45 has an exact release gate'
contains "$ROOT/installer/core/detect.sh" 'debian)' && pass 'Debian ID has an explicit backend route' || fail 'Debian ID has an explicit backend route'
contains "$ROOT/installer/core/detect.sh" 'ubuntu)' && pass 'Ubuntu ID has an explicit backend route' || fail 'Ubuntu ID has an explicit backend route'
contains "$ROOT/installer/distros/debian/packages.sh" "[qt6-svg]='qt6-svg-plugins'" && pass 'Debian maps Qt SVG to the runtime image plugin package' || fail 'Debian maps Qt SVG to the runtime image plugin package'
contains "$ROOT/installer/distros/ubuntu/packages.sh" "[qt6-svg]='qt6-svg-plugins'" && pass 'Ubuntu maps Qt SVG to the runtime image plugin package' || fail 'Ubuntu maps Qt SVG to the runtime image plugin package'
contains "$ROOT/installer/catalog/requirements.sh" 'jetbrains-mono' && pass 'Font capability is named for the actual JetBrains Mono package' || fail 'Font capability is named for the actual JetBrains Mono package'
not_contains "$ROOT/installer/catalog/requirements.sh" 'nerd-font' && pass 'Installer does not mislabel plain JetBrains Mono as a Nerd Font' || fail 'Installer does not mislabel plain JetBrains Mono as a Nerd Font'
contains "$ROOT/installer/distros/fedora/packages.sh" "[jetbrains-mono]='jetbrains-mono-fonts'" && pass 'Fedora maps JetBrains Mono to the matching package' || fail 'Fedora maps JetBrains Mono to the matching package'
contains "$ROOT/installer/distros/debian/packages.sh" "[jetbrains-mono]='fonts-jetbrains-mono'" && pass 'Debian maps JetBrains Mono to the matching package' || fail 'Debian maps JetBrains Mono to the matching package'
contains "$ROOT/installer/distros/ubuntu/packages.sh" "[jetbrains-mono]='fonts-jetbrains-mono'" && pass 'Ubuntu maps JetBrains Mono to the matching package' || fail 'Ubuntu maps JetBrains Mono to the matching package'
contains "$ROOT/installer/distros/arch/packages.sh" "[jetbrains-mono]='ttf-jetbrains-mono'" && pass 'Arch maps the plain JetBrains Mono package, not a Nerd Font' || fail 'Arch maps the plain JetBrains Mono package, not a Nerd Font'
contains "$ROOT/installer/catalog/requirements.sh" 'util-linux' && pass 'Installer lock and process wrappers declare util-linux' || fail 'Installer lock and process wrappers declare util-linux'
contains "$ROOT/installer/catalog/requirements.sh" 'diffutils' && pass 'Backup comparison declares diffutils' || fail 'Backup comparison declares diffutils'
contains "$ROOT/installer/core/plan.sh" 'util-linux) sp_have flock' && pass 'util-linux capability checks flock/setpriv/setsid' || fail 'util-linux capability checks flock/setpriv/setsid'
contains "$ROOT/installer/core/plan.sh" 'diffutils) sp_have diff' && pass 'diffutils capability checks diff' || fail 'diffutils capability checks diff'
contains "$ROOT/installer/core/plan.sh" 'procps) sp_have pkill' && pass 'procps capability checks pkill' || fail 'procps capability checks pkill'
contains "$ROOT/installer/catalog/requirements.sh" 'procps' && pass 'Clipboard cleanup declares procps' || fail 'Clipboard cleanup declares procps'
contains "$ROOT/installer/core/plan.sh" 'sp_fedora_tuned_ppd_installed' && pass 'Fedora TuneD PPD provider is recognized even when inactive' || fail 'Fedora TuneD PPD provider is recognized even when inactive'
contains "$ROOT/installer/integrations/systemd.sh" 'tuned-ppd.service' && pass 'Fedora TuneD PPD service is reconciled without adding a second provider' || fail 'Fedora TuneD PPD service is reconciled without adding a second provider'
contains "$ROOT/installer/integrations/systemd.sh" 'active_provider' && pass 'Fedora service reconciliation prioritizes active providers' || fail 'Fedora service reconciliation prioritizes active providers'
contains "$ROOT/installer/integrations/systemd.sh" 'active_count > 1' && pass 'Fedora service reconciliation detects multiple active providers' || fail 'Fedora service reconciliation detects multiple active providers'
contains "$ROOT/installer/integrations/systemd.sh" 'tlp_backend_active' && pass 'Fedora service reconciliation respects an active TLP backend' || fail 'Fedora service reconciliation respects an active TLP backend'
contains "$ROOT/installer/integrations/systemd.sh" 'tlp_provider_conflict' && pass 'Fedora service reconciliation prevents TLP/PPD conflicts' || fail 'Fedora service reconciliation prevents TLP/PPD conflicts'
contains "$ROOT/installer/core/plan.sh" 'sp_fedora_power_profile_provider_count' && pass 'Fedora counts installed PowerProfiles provider packages' || fail 'Fedora counts installed PowerProfiles provider packages'
contains "$ROOT/installer/integrations/systemd.sh" 'package_provider_count > 1' && pass 'Fedora refuses ambiguous selection among inactive providers' || fail 'Fedora refuses ambiguous selection among inactive providers'
contains "$ROOT/installer/core/plan.sh" 'sp_fedora_tlp_pd_installed' && pass 'Fedora TLP profile daemon provider is recognized' || fail 'Fedora TLP profile daemon provider is recognized'
contains "$ROOT/installer/core/plan.sh" 'TLP is installed without tlp-pd' && pass 'Fedora TLP-only conflict is reported instead of installing another provider' || fail 'Fedora TLP-only conflict is reported instead of installing another provider'
contains "$ROOT/installer/integrations/systemd.sh" 'tlp-pd.service' && pass 'Fedora TLP profile service is reconciled when installed' || fail 'Fedora TLP profile service is reconciled when installed'
contains "$ROOT/installer/core/deployment.sh" 'sp_prepare_shaders "$stage/shaders"' && pass 'Shaders are prepared in staging before Quickshell replacement' || fail 'Shaders are prepared in staging before Quickshell replacement'
contains "$ROOT/installer/core/main.sh" 'sp_rollback_failed_deployment' && pass 'Failed deployment phases have automatic configuration rollback' || fail 'Failed deployment phases have automatic configuration rollback'
contains "$ROOT/installer/core/main.sh" 'Post-deployment runtime validation failed; Quickshell activation was skipped' && pass 'Mandatory runtime validation gates Quickshell activation' || fail 'Mandatory runtime validation gates Quickshell activation'
contains "$ROOT/installer/core/detect.sh" 'ID_LIKE is informational only' && pass 'ID_LIKE never triggers implicit fallback' || fail 'ID_LIKE never triggers implicit fallback'
contains "$ROOT/installer/core/detect.sh" 'silverblue|kinoite|sericea|onyx|sway-atomic|budgie-atomic' && pass 'Fedora Atomic variants are rejected' || fail 'Fedora Atomic variants are rejected'
not_contains "$ROOT/installer/core/detect.sh" 'opensuse)' && pass 'openSUSE is not in the supported ID allowlist' || fail 'openSUSE is not in the supported ID allowlist'
contains "$ROOT/installer/core/plan.sh" '6.12.0' && pass 'Qt 6.12 shader baseline is encoded in planning' || fail 'Qt 6.12 shader baseline is encoded in planning'
contains "$ROOT/installer/core/plan.sh" 'quickshell) sp_have qs ;;' && pass 'Quickshell runtime detection uses the actual qs executable' || fail 'Quickshell runtime detection uses the actual qs executable'
contains "$ROOT/installer/core/plan.sh" 'ffmpeg) sp_have ffmpeg ;;' && pass 'FFmpeg runtime detection accepts an existing ffmpeg executable' || fail 'FFmpeg runtime detection accepts an existing ffmpeg executable'
contains "$ROOT/installer/distros/fedora/packages.sh" "[qt6-base]='qt6-qtbase'" && pass 'Fedora Qt runtime map excludes development headers' || fail 'Fedora Qt runtime map excludes development headers'
not_contains "$ROOT/installer/distros/fedora/packages.sh" 'qt6-qtbase-devel' && pass 'Fedora Qt runtime map does not install qtbase development files' || fail 'Fedora Qt runtime map does not install qtbase development files'
contains "$ROOT/installer/integrations/systemd.sh" 'tuned-ppd.service' && pass 'Fedora tuned-ppd compatibility provider is reconciled' || fail 'Fedora tuned-ppd compatibility provider is reconciled'
contains "$ROOT/installer/distros/fedora/packages.sh" "[power-profiles-daemon]='tuned-ppd'" && pass 'Fedora 44 defaults to its native TuneD PPD provider' || fail 'Fedora 44 defaults to its native TuneD PPD provider'
contains "$ROOT/installer/core/plan.sh" 'Existing provider packages' && pass 'Inactive installed Fedora providers are reported separately from active runtime APIs' || fail 'Inactive installed Fedora providers are reported separately from active runtime APIs'
contains "$ROOT/installer/core/plan.sh" 'NameHasOwner' && pass 'Fedora TuneD provider verifies D-Bus name ownership' || fail 'Fedora TuneD provider verifies D-Bus name ownership'
contains "$ROOT/installer/core/plan.sh" 'org.freedesktop.UPower.PowerProfiles' && pass 'Fedora runtime provider detection relies on the exported PowerProfiles D-Bus API' || fail 'Fedora runtime provider detection relies on the exported PowerProfiles D-Bus API'
not_contains "$ROOT/installer/core/plan.sh" 'systemctl is-active --quiet "$service"' && pass 'Fedora D-Bus runtime detection does not require a hard-coded provider unit name' || fail 'Fedora D-Bus runtime detection does not require a hard-coded provider unit name'
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
if bash "$ROOT/tests/test-quickshell-activation.sh"; then pass 'Quickshell activation and process rollback fixtures'; else fail 'Quickshell activation and process rollback fixtures'; fi
if bash "$ROOT/tests/test-fedora-power-provider.sh"; then pass 'Fedora power-provider regression fixtures'; else fail 'Fedora power-provider regression fixtures'; fi
if bash "$ROOT/tests/test-deployment-transaction.sh"; then pass 'Deployment staging and rollback regression fixtures'; else fail 'Deployment staging and rollback regression fixtures'; fi
if bash "$ROOT/tests/test-pacman-safety.sh"; then pass 'Arch pacman synchronization and authorization fixtures'; else fail 'Arch pacman synchronization and authorization fixtures'; fi
if bash "$ROOT/tests/test-installer-lock.sh"; then pass 'Installer concurrency lock fixtures'; else fail 'Installer concurrency lock fixtures'; fi
if bash "$ROOT/tests/test-transaction-journal.sh"; then pass 'Durable installer journal integrity and concurrency fixtures'; else fail 'Durable installer journal integrity and concurrency fixtures'; fi
if bash "$ROOT/tests/test-shader-plan.sh"; then pass 'Qt Shader Tools planning fixtures'; else fail 'Qt Shader Tools planning fixtures'; fi
if bash "$ROOT/tests/test-power-profile-api.sh"; then pass 'PowerProfiles D-Bus API fixtures'; else fail 'PowerProfiles D-Bus API fixtures'; fi
if bash "$ROOT/tests/test-hyprland-touchpad-key.sh"; then pass 'Hyprland Lua touchpad key fixtures'; else fail 'Hyprland Lua touchpad key fixtures'; fi
if bash "$ROOT/tests/test-apt-repository-bootstrap.sh"; then pass 'Read-only official APT repository validation fixtures'; else fail 'Read-only official APT repository validation fixtures'; fi
if bash "$ROOT/tests/test-dependency-failure-gate.sh"; then pass 'Dependency failure blocks all deployment modes'; else fail 'Dependency failure blocks all deployment modes'; fi
if bash "$ROOT/tests/test-package-install-failure.sh"; then pass 'Production planner propagates package transaction failure'; else fail 'Production planner propagates package transaction failure'; fi
if bash "$ROOT/tests/test-dependency-only-runtime-gate.sh"; then pass 'Dependency-only mode gates desktop integration on runtime verification'; else fail 'Dependency-only mode gates desktop integration on runtime verification'; fi
if bash "$ROOT/tests/test-private-prefix-validation.sh"; then pass 'CMake install manifests are confined to the private prefix'; else fail 'CMake install manifests are confined to the private prefix'; fi
if bash "$ROOT/tests/test-fedora-hyprland-source-fetch-safety.sh"; then pass 'Fedora source fetch preserves pre-existing archive files'; else fail 'Fedora source fetch preserves pre-existing archive files'; fi
if bash "$ROOT/tests/test-fedora-hyprland-build-provenance.sh"; then pass 'Fedora source-build provenance is immutable and complete'; else fail 'Fedora source-build provenance is immutable and complete'; fi
if python3 "$ROOT/tests/test-fedora-dnf-repository-snapshot.py"; then pass 'DNF5 repository provenance resolves real config files and symlinks'; else fail 'DNF5 repository provenance resolves real config files and symlinks'; fi
if bash "$ROOT/tests/test-fedora-host-provider.sh"; then pass 'Fedora host-provider preflight rejects unsupported and unsafe environments'; else fail 'Fedora host-provider preflight rejects unsupported and unsafe environments'; fi
if python3 "$ROOT/tests/test-fedora-host-manifest.py"; then pass 'Fedora host artifact manifest verifies ownership and path containment'; else fail 'Fedora host artifact manifest verifies ownership and path containment'; fi
if python3 "$ROOT/tests/test-fedora-host-deploy.py"; then pass 'Fedora host publication uses atomic no-replace directory rename'; else fail 'Fedora host publication uses atomic no-replace directory rename'; fi
if python3 "$ROOT/tests/test-fedora-host-build-lock.py"; then pass 'Fedora host build lock pins images and source identities'; else fail 'Fedora host build lock pins images and source identities'; fi
if python3 "$ROOT/tests/test-fedora-copr-provider-lock.py"; then pass 'Fedora COPR provider lock pins trust and package provenance'; else fail 'Fedora COPR provider lock pins trust and package provenance'; fi
if python3 "$ROOT/tests/test-fedora-hyprland-copr-provider.py"; then pass 'Fedora COPR provider validates repository, key and RPM ownership'; else fail 'Fedora COPR provider validates repository, key and RPM ownership'; fi
if python3 -m py_compile "$ROOT/tools/fedora-hyprland-copr-provider.py"; then pass 'Fedora COPR provider helper compiles'; else fail 'Fedora COPR provider helper compiles'; fi
if bash "$ROOT/tests/test-fedora-host-prepare-session.sh"; then pass 'Fedora host session launcher is validated and collision-safe'; else fail 'Fedora host session launcher is validated and collision-safe'; fi
if bash "$ROOT/tests/test-fedora-host-user-integration.sh"; then pass 'Fedora Hyprland user systemd integration is idempotent and collision-safe'; else fail 'Fedora Hyprland user systemd integration is idempotent and collision-safe'; fi
printf '\nSmoke assertions: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
