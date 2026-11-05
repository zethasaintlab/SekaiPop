#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
FETCHER="$ROOT/tools/fedora-hyprland-source-fetch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/dest"
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
printf 'git invoked\n' >> "$GIT_LOG"
exit 99
GIT
chmod +x "$TMP/bin/git"
export GIT_LOG="$TMP/git.log"
export PATH="$TMP/bin:$PATH"
ARCHIVE="$TMP/dest/lua-5.5.1.tar.gz"
PART="$ARCHIVE.part"
printf 'preserve archive\n' > "$ARCHIVE"
if "$FETCHER" "$TMP/dest" >/dev/null 2>&1; then
    printf '[FAIL] existing archive must be rejected\n' >&2
    exit 1
fi
grep -Fq 'preserve archive' "$ARCHIVE" || { printf '[FAIL] existing archive was modified\n' >&2; exit 1; }
[[ ! -e "$GIT_LOG" ]] || { printf '[FAIL] git ran before archive collision check\n' >&2; exit 1; }
printf '[PASS] existing archive is preserved and rejected before network activity\n'
rm -f -- "$ARCHIVE"
printf 'preserve partial\n' > "$PART"
if "$FETCHER" "$TMP/dest" >/dev/null 2>&1; then
    printf '[FAIL] existing partial archive must be rejected\n' >&2
    exit 1
fi
grep -Fq 'preserve partial' "$PART" || { printf '[FAIL] existing partial archive was modified\n' >&2; exit 1; }
[[ ! -e "$GIT_LOG" ]] || { printf '[FAIL] git ran before partial collision check\n' >&2; exit 1; }
printf '[PASS] existing partial archive is preserved and rejected before network activity\n'
