#!/usr/bin/env bash
# Durable installer journal shared by native dependencies and desktop deployment.
SP_TRANSACTION_JOURNAL=''
SP_TRANSACTION_FINALIZED=0

sp_transaction_journal_begin() {
    SP_TRANSACTION_JOURNAL_DIR="$SP_STATE_DIR/installer-transactions"
    [[ ! -L "$SP_STATE_DIR" ]] || sp_die "Refusing symlinked installer state directory: $SP_STATE_DIR"
    [[ ! -L "$SP_TRANSACTION_JOURNAL_DIR" ]] || sp_die "Refusing symlinked transaction journal directory: $SP_TRANSACTION_JOURNAL_DIR"
    mkdir -p -- "$SP_TRANSACTION_JOURNAL_DIR" || sp_die 'Could not create the installer transaction journal directory.'
    [[ -d "$SP_TRANSACTION_JOURNAL_DIR" && ! -L "$SP_TRANSACTION_JOURNAL_DIR" && -O "$SP_TRANSACTION_JOURNAL_DIR" ]] ||
        sp_die 'Installer transaction journal directory must be a real directory owned by the current user.'
    chmod 0700 "$SP_TRANSACTION_JOURNAL_DIR" || sp_die 'Could not secure installer transaction journal directory.'
    bash "$SP_ROOT/tools/transaction-journal.sh" recover-check "$SP_TRANSACTION_JOURNAL_DIR" ||
        sp_die "An earlier installer transaction is unfinished or requires recovery. Inspect journals in $SP_TRANSACTION_JOURNAL_DIR before retrying."
    SP_TRANSACTION_JOURNAL="$SP_TRANSACTION_JOURNAL_DIR/$SP_TIMESTAMP.json"
    bash "$SP_ROOT/tools/transaction-journal.sh" init "$SP_TRANSACTION_JOURNAL" "$SP_TIMESTAMP" "$" \
        "$SP_DISTRO_ID" "$SP_DISTRO_VERSION" "$SP_BACKEND" "$SP_PROFILE" "$SP_HYPR" ||
        sp_die 'Could not initialize a durable installer transaction journal.'
    sp_info "Transaction journal: $SP_TRANSACTION_JOURNAL"
}

sp_transaction_event() {
    local name="$1" detail="${2:-}"
    [[ -n "$SP_TRANSACTION_JOURNAL" ]] || return 0
    bash "$SP_ROOT/tools/transaction-journal.sh" event "$SP_TRANSACTION_JOURNAL" "$name" "$detail" ||
        sp_die "Could not persist installer transaction event: $name"
}

sp_transaction_finish() {
    local status="$1" detail="${2:-}"
    [[ -n "$SP_TRANSACTION_JOURNAL" ]] || return 0
    bash "$SP_ROOT/tools/transaction-journal.sh" finish "$SP_TRANSACTION_JOURNAL" "$status" "$detail" ||
        sp_die "Could not finalize installer transaction as $status."
    SP_TRANSACTION_FINALIZED=1
}

sp_transaction_exit_trap() {
    local exit_status="${1:-1}"
    if [[ -n "$SP_TRANSACTION_JOURNAL" && "$SP_TRANSACTION_FINALIZED" != 1 ]]; then
        bash "$SP_ROOT/tools/transaction-journal.sh" finish "$SP_TRANSACTION_JOURNAL" needs_recovery \
            "Installer exited unexpectedly with status $exit_status." >/dev/null 2>&1 ||
            printf '[FAIL] Could not mark interrupted transaction for recovery: %s\n' "$SP_TRANSACTION_JOURNAL" >&2
    fi
    return "$exit_status"
}
