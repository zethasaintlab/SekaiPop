#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
HELPER="$ROOT/tools/transaction-journal.sh"
TMP="$(mktemp -d /tmp/sekaipop-journal.XXXXXX)"
trap 'rm -rf -- "$TMP"' EXIT
DIR="$TMP/state/installer-transactions"
mkdir -p "$DIR"
run() { bash "$HELPER" "$@"; }
pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; exit 1; }

# Exercise the exact shell API sourced by installer/core/main.sh.
export SEKAIPOP_INSTALLER_ROOT="$ROOT" XDG_STATE_HOME="$TMP/wrapper-state" HOME="$TMP/home"
mkdir -p "$HOME"
source "$ROOT/installer/core/main.sh"
SP_TIMESTAMP="wrapper-test-$$"
SP_DISTRO_ID=fedora SP_DISTRO_VERSION=45 SP_BACKEND=dnf5 SP_PROFILE=minimal SP_HYPR=skip
sp_transaction_journal_begin
sp_transaction_event wrapper.integration "journal wrapper exercised"
sp_transaction_finish committed "wrapper transaction committed"
WRAPPER_JOURNAL="$XDG_STATE_HOME/sekaipop/installer-transactions/$SP_TIMESTAMP.journal"
grep -Fq 'wrapper.integration' "$WRAPPER_JOURNAL" || fail 'Installer shell wrapper did not persist events'
metadata="$(base64 -d <<< "$(awk -F '\t' '$1 == "metadata_b64" {print $2}' "$WRAPPER_JOURNAL")")"
[[ "$metadata" == $'fedora\t45\tdnf5\tminimal\tskip' ]] || fail 'Installer shell wrapper recorded incorrect metadata'
pass 'Installer shell wrapper records metadata and transaction events'

JOURNAL="$DIR/tx-one.journal"
run init "$JOURNAL" tx-one "$$" fedora 45 dnf5 standard merge
grep -Fqx $'schema\tsekaipop-transaction-v1' "$JOURNAL" || fail 'Journal schema header is missing'
grep -Fqx $'status\tactive' "$JOURNAL" || fail 'New transaction is not active'
[[ "$(stat -c %a "$JOURNAL")" == 600 ]] || fail 'Journal permissions are not 0600'
if run recover-check "$DIR"; then fail 'A second transaction was allowed while the first is live'; fi
[[ "$(awk -F '\\t' '$1 == "status" { value=$2 } END { print value }' "$JOURNAL")" == active ]] || fail 'Live transaction was incorrectly marked stale'
run event "$JOURNAL" provider.preflight 'Fedora 45 supported'
run event "$JOURNAL" podman.validated 'rootless=true'
grep -Fq $'event\t' "$JOURNAL" || fail 'Transaction events were not recorded'
if run event "$JOURNAL" 'invalid event' ''; then fail 'Invalid event name was accepted'; fi
if run init "$JOURNAL" tx-one "$$" fedora 45 dnf5 standard merge; then fail 'Existing journal was overwritten'; fi
run finish "$JOURNAL" committed 'all required phases validated'
[[ "$(awk -F '\t' '$1 == "status" { value=$2 } END { print value }' "$JOURNAL")" == committed ]] || fail 'Committed status was not persisted'
if run event "$JOURNAL" late.event ''; then fail 'Committed journal accepted another event'; fi
pass 'Journal lifecycle, state transitions and event validation'

CONCURRENT="$DIR/tx-concurrent.journal"
run init "$CONCURRENT" tx-concurrent "$$" fedora 45 dnf5 standard merge
for index in {1..12}; do run event "$CONCURRENT" "worker-$index" "concurrent event $index" & done
wait
count="$(grep -c $'^event\t' "$CONCURRENT")"
[[ "$count" == 13 ]] || fail "Concurrent journal writes were lost (expected 13 events, found $count)"
pass 'Concurrent writers are serialized without lost events'

LINKED="$DIR/linked.journal"
ln -s "$JOURNAL" "$LINKED"
if run event "$LINKED" attack ''; then fail 'Symlinked journal was accepted'; fi
rm -f "$LINKED"
LOCK="$CONCURRENT.lock"
rm -f "$LOCK"
ln -s "$JOURNAL" "$LOCK"
if run event "$CONCURRENT" lock.attack ''; then fail 'Symlinked lock was accepted'; fi
rm -f "$LOCK"
pass 'Symlinked journals and lock files are rejected'

STALE="$DIR/tx-stale.journal"
run init "$STALE" tx-stale 99999999 fedora 45 dnf5 standard merge
if run recover-check "$DIR"; then fail 'Interrupted transaction did not block a new install'; fi
[[ "$(awk -F '\t' '$1 == "status" { value=$2 } END { print value }' "$STALE")" == needs_recovery ]] || fail 'Interrupted transaction was not marked needs_recovery'
if run recover-check "$DIR"; then fail 'Recovery-required transaction did not block retry'; fi
pass 'Stale transaction detection fails closed and remains durable'

printf '\nDurable transaction journal fixtures passed.\n'
