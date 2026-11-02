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
chmod +x "$TMP/bin/qs"
PATH="$TMP/bin"
export PATH
if sp_runtime_requirement_present quickshell; then
    printf '[PASS] Quickshell runtime is detected from the qs executable alone\n'
else
    printf '[FAIL] Quickshell runtime incorrectly requires a quickshell executable\n' >&2
    exit 1
fi
