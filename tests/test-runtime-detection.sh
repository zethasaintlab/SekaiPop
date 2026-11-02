#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
ORIGINAL_PATH="$PATH"
TMP="$(mktemp -d /tmp/sekaipop-runtime.XXXXXX)"
trap 'PATH="$ORIGINAL_PATH"; rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin"
export SEKAIPOP_INSTALLER_ROOT="$ROOT"
source "$ROOT/installer/core/main.sh"

cat > "$TMP/bin/qs" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat > "$TMP/bin/ffmpeg" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat > "$TMP/bin/rpm" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == -q && "${2:-}" == tuned-ppd && "${MOCK_TUNED_PPD_INSTALLED:-0}" == 1 ]]
MOCK
cat > "$TMP/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == is-active && "${2:-}" == --quiet && "${3:-}" == tuned-ppd.service && "${MOCK_TUNED_PPD_ACTIVE:-0}" == 1 ]]
MOCK
chmod +x "$TMP/bin/qs" "$TMP/bin/ffmpeg" "$TMP/bin/rpm" "$TMP/bin/systemctl"
PATH="$TMP/bin"
export PATH

assert_present() {
    local capability="$1" label="$2"
    if sp_runtime_requirement_present "$capability"; then
        printf '[PASS] %s\n' "$label"
    else
        printf '[FAIL] %s\n' "$label" >&2
        exit 1
    fi
}
assert_absent() {
    local capability="$1" label="$2"
    if sp_runtime_requirement_present "$capability"; then
        printf '[FAIL] %s\n' "$label" >&2
        exit 1
    else
        printf '[PASS] %s\n' "$label"
    fi
}

assert_present quickshell 'Quickshell is detected from qs executable'
assert_present ffmpeg 'FFmpeg is detected from executable without package-name coupling'

export SP_DISTRO_ID=fedora MOCK_TUNED_PPD_INSTALLED=1 MOCK_TUNED_PPD_ACTIVE=1
assert_present power-profiles-daemon 'Active Fedora tuned-ppd satisfies the power-profile capability'

export MOCK_TUNED_PPD_ACTIVE=0
assert_absent power-profiles-daemon 'Inactive tuned-ppd does not satisfy the power-profile capability'

export MOCK_TUNED_PPD_ACTIVE=1 MOCK_TUNED_PPD_INSTALLED=0
assert_absent power-profiles-daemon 'Uninstalled tuned-ppd does not satisfy the power-profile capability'

cat > "$TMP/bin/powerprofilesctl" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$TMP/bin/powerprofilesctl"
assert_present power-profiles-daemon 'Native powerprofilesctl satisfies the power-profile capability'

printf '\nRuntime detection fixtures passed.\n'
