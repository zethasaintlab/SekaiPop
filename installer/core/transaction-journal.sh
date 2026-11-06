#!/usr/bin/env bash
# Durable installer journal shared by native dependencies and desktop deployment.
SP_TRANSACTION_JOURNAL=''

sp_transaction_journal_begin() {
    local metadata
    sp_have python3 || sp_die 'Python 3 is required for durable installer transaction journaling.'
    SP_TRANSACTION_JOURNAL_DIR="$SP_STATE_DIR/installer-transactions"
    [[ ! -L "$SP_STATE_DIR" ]] || sp_die "Refusing symlinked installer state directory: $SP_STATE_DIR"
    [[ ! -L "$SP_TRANSACTION_JOURNAL_DIR" ]] || sp_die "Refusing symlinked transaction journal directory: $SP_TRANSACTION_JOURNAL_DIR"
    mkdir -p -- "$SP_TRANSACTION_JOURNAL_DIR" || sp_die 'Could not create the installer transaction journal directory.'
    [[ -d "$SP_TRANSACTION_JOURNAL_DIR" && ! -L "$SP_TRANSACTION_JOURNAL_DIR" && -O "$SP_TRANSACTION_JOURNAL_DIR" ]] ||
        sp_die 'Installer transaction journal directory must be a real directory owned by the current user.'
    chmod 0700 "$SP_TRANSACTION_JOURNAL_DIR" || sp_die 'Could not secure installer transaction journal directory.'
    SP_TRANSACTION_JOURNAL="$SP_TRANSACTION_JOURNAL_DIR/$SP_TIMESTAMP.json"
    metadata="$(python3 -c 'import json,os; print(json.dumps({"distro":os.environ.get("SP_DISTRO_ID","unknown"),"release":os.environ.get("SP_DISTRO_VERSION","unknown"),"backend":os.environ.get("SP_BACKEND","unknown"),"profile":os.environ.get("SP_PROFILE","unknown"),"hypr_mode":os.environ.get("SP_HYPR","unknown")}))')" ||
        sp_die 'Could not encode installer transaction metadata.'
    python3 "$SP_ROOT/tools/transaction-journal.py" init "$SP_TRANSACTION_JOURNAL" "$SP_TIMESTAMP" --metadata "$metadata" ||
        sp_die 'Could not initialize a durable installer transaction journal.'
    sp_info "Transaction journal: $SP_TRANSACTION_JOURNAL"
}

sp_transaction_event() {
    local name="$1" detail="${2:-}"
    [[ -n "$SP_TRANSACTION_JOURNAL" ]] || return 0
    python3 "$SP_ROOT/tools/transaction-journal.py" event "$SP_TRANSACTION_JOURNAL" "$name" "$detail" ||
        sp_die "Could not persist installer transaction event: $name"
}

sp_transaction_finish() {
    local status="$1" detail="${2:-}"
    [[ -n "$SP_TRANSACTION_JOURNAL" ]] || return 0
    python3 "$SP_ROOT/tools/transaction-journal.py" finish "$SP_TRANSACTION_JOURNAL" "$status" "$detail" ||
        sp_die "Could not finalize installer transaction as $status."
}
