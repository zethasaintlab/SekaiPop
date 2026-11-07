#!/usr/bin/env bash
set -Eeuo pipefail

fail() { printf 'transaction-journal: %s\n' "$*" >&2; exit 1; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
boot_id() { [[ -r /proc/sys/kernel/random/boot_id ]] && cat /proc/sys/kernel/random/boot_id || printf unknown; }
process_start_time() {
    local pid="$1" content rest
    [[ -r "/proc/$pid/stat" ]] || return 1
    content="$(<"/proc/$pid/stat")"
    rest="${content##*) }"
    local -a fields=()
    read -r -a fields <<< "$rest"
    [[ -n "${fields[19]:-}" ]] || return 1
    printf '%s\n' "${fields[19]}"
}
secure_directory() {
    local directory="$1" current component
    [[ "$directory" == /* ]] || fail 'transaction directory must be absolute'
    current=/
    local -a components=()
    IFS=/ read -r -a components <<< "${directory#/}"
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        [[ "$component" != . && "$component" != .. ]] || fail "non-normalized transaction path component: $component"
        current="${current%/}/$component"
        [[ ! -L "$current" ]] || fail "symlink path component: $current"
        if [[ ! -e "$current" ]]; then
            mkdir -m 0700 -- "$current" || fail "cannot create transaction directory component: $current"
        fi
        [[ -d "$current" && ! -L "$current" ]] || fail "non-directory path component: $current"
    done
    [[ "$(stat -c %u -- "$directory")" == "$(id -u)" ]] || fail "transaction directory is not owned by the current user: $directory"
    chmod 0700 -- "$directory" || fail "cannot secure transaction directory: $directory"
}
secure_journal() {
    local journal="$1"
    [[ "$journal" == /* ]] || fail 'journal path must be absolute'
    secure_directory "$(dirname -- "$journal")"
    [[ ! -L "$journal" ]] || fail "refusing symlinked journal: $journal"
    if [[ -e "$journal" ]]; then
        [[ -f "$journal" && "$(stat -c %u -- "$journal")" == "$(id -u)" && "$(stat -c %h -- "$journal")" == 1 ]] || fail "journal is not a regular, singly-linked user-owned file: $journal"
        local mode
        mode="$(stat -c %a -- "$journal")"
        (( (8#$mode & 077) == 0 )) || fail "journal permissions are too broad: $journal"
    fi
}
with_lock() {
    local journal="$1" lock_file="${1}.lock"
    [[ ! -L "$lock_file" ]] || fail "refusing symlinked transaction lock: $lock_file"
    exec {LOCK_FD}>> "$lock_file" || fail "cannot open transaction lock: $lock_file"
    [[ -f "$lock_file" && "$(stat -c %u -- "$lock_file")" == "$(id -u)" && "$(stat -c %h -- "$lock_file")" == 1 ]] ||
        fail "transaction lock is not a regular, singly-linked user-owned file: $lock_file"
    chmod 0600 -- "$lock_file" || fail "cannot secure transaction lock: $lock_file"
    flock -x "$LOCK_FD" || fail "cannot acquire transaction lock: $lock_file"
}
latest_status() {
    awk -F '\t' '$1 == "status" { value=$2 } END { if (value != "") print value; else exit 1 }' "$1"
}
field_value() {
    awk -F '\t' -v key="$2" '$1 == key { value=$2 } END { if (value != "") print value; else exit 1 }' "$1"
}
append_record() {
    local journal="$1" record="$2"
    printf '%s\n' "$record" >> "$journal" || fail "cannot append transaction record: $journal"
    sync -f "$journal" || fail "cannot synchronize transaction journal: $journal"
}
init_journal() {
    local journal="$1" transaction_id="$2" pid="$3" distro="$4" release="$5" backend="$6" profile="$7" hypr_mode="$8"
    secure_journal "$journal"
    with_lock "$journal"
    [[ ! -e "$journal" ]] || fail "transaction journal already exists: $journal"
    ( set -o noclobber; : > "$journal" ) 2>/dev/null || fail "cannot create transaction journal: $journal"
    chmod 0600 "$journal"
    local started boot start metadata
    started="$(now_utc)"
    boot="$(boot_id)"
    start="$(process_start_time "$pid" || true)"
    metadata="$(printf '%s\t%s\t%s\t%s\t%s' "$distro" "$release" "$backend" "$profile" "$hypr_mode" | base64 -w0)"
    {
        printf 'schema\tsekaipop-transaction-v1\n'
        printf 'transaction_id\t%s\n' "$transaction_id"
        printf 'pid\t%s\n' "$pid"
        printf 'pid_start_time\t%s\n' "$start"
        printf 'boot_id\t%s\n' "$boot"
        printf 'metadata_b64\t%s\n' "$metadata"
        printf 'status\tactive\n'
        printf 'event\t%s\ttransaction_started\t\n' "$started"
    } >> "$journal"
    sync -f "$journal"
    sync -f "$(dirname -- "$journal")"
}
append_event() {
    local journal="$1" name="$2" detail="$3" current encoded
    [[ "$name" =~ ^[a-z][a-z0-9_.-]{0,63}$ ]] || fail 'invalid event name'
    (( ${#detail} <= 2048 )) || fail 'event detail exceeds 2048 characters'
    secure_journal "$journal"
    [[ -f "$journal" ]] || fail "transaction journal does not exist: $journal"
    with_lock "$journal"
    current="$(latest_status "$journal")" || fail 'journal has no valid status record'
    [[ "$current" == active ]] || fail "cannot append to a $current transaction"
    encoded="$(printf '%s' "$detail" | base64 -w0)"
    append_record "$journal" "$(printf 'event\t%s\t%s\t%s' "$(now_utc)" "$name" "$encoded")"
}
finish_journal() {
    local journal="$1" status="$2" detail="$3" encoded current
    [[ "$status" == committed || "$status" == failed || "$status" == needs_recovery ]] || fail "invalid final status: $status"
    secure_journal "$journal"
    [[ -f "$journal" ]] || fail "transaction journal does not exist: $journal"
    with_lock "$journal"
    current="$(latest_status "$journal")" || fail 'journal has no valid status record'
    [[ "$current" == active ]] || fail "cannot finalize a $current transaction"
    encoded="$(printf '%s' "$detail" | base64 -w0)"
    append_record "$journal" "$(printf 'event\t%s\ttransaction_%s\t%s' "$(now_utc)" "$status" "$encoded")"
    append_record "$journal" "$(printf 'status\t%s' "$status")"
}
recover_check() {
    local directory="$1" journal status pid recorded_start recorded_boot current_start current_boot blocked=0
    secure_directory "$directory"
    shopt -s nullglob
    local -a journals=("$directory"/*.journal)
    shopt -u nullglob
    for journal in "${journals[@]}"; do
        secure_journal "$journal"
        with_lock "$journal"
        status="$(latest_status "$journal")" || fail "invalid journal status: $journal"
        if [[ "$status" == needs_recovery ]]; then
            printf 'Recovery required: %s\n' "$journal" >&2
            blocked=1
            continue
        fi
        [[ "$status" == active ]] || continue
        pid="$(field_value "$journal" pid || true)"
        recorded_start="$(field_value "$journal" pid_start_time || true)"
        recorded_boot="$(field_value "$journal" boot_id || true)"
        current_boot="$(boot_id)"
        current_start=""
        if [[ "$pid" =~ ^[0-9]+$ ]]; then current_start="$(process_start_time "$pid" 2>/dev/null || true)"; fi
        if [[ -n "$pid" && "$recorded_boot" == "$current_boot" && -n "$recorded_start" && "$current_start" == "$recorded_start" ]]; then
            printf 'An installer transaction is still active (PID %s): %s\n' "$pid" "$journal" >&2
            blocked=1
            continue
        fi
        append_record "$journal" "$(printf 'event\t%s\ttransaction_interrupted\t%s' "$(now_utc)" "$(printf '%s' 'The owning installer process is no longer alive on the recorded boot.' | base64 -w0)")"
        append_record "$journal" 'status	needs_recovery'
        printf 'Interrupted transaction requires inspection: %s\n' "$journal" >&2
        blocked=1
    done
    (( blocked == 0 )) || fail 'unfinished transaction(s) require inspection before a new install'
}
case "${1:-}" in
    init) (($# == 9)) || fail 'usage: init JOURNAL ID PID DISTRO RELEASE BACKEND PROFILE HYPR_MODE'; init_journal "${@:2}" ;;
    event) (($# == 4)) || fail 'usage: event JOURNAL NAME DETAIL'; append_event "${@:2}" ;;
    finish) (($# == 4)) || fail 'usage: finish JOURNAL STATUS DETAIL'; finish_journal "${@:2}" ;;
    recover-check) (($# == 2)) || fail 'usage: recover-check DIRECTORY'; recover_check "$2" ;;
    *) fail 'unknown journal command' ;;
esac
