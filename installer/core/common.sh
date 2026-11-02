#!/usr/bin/env bash
# Shared, side-effect-free primitives. Sourced by every public entrypoint.

: "${SEKAIPOP_INSTALLER_ROOT:?SEKAIPOP_INSTALLER_ROOT is not set}"
SP_ROOT="$SEKAIPOP_INSTALLER_ROOT"
SP_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SP_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
SP_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
SP_QS_DEST="$SP_CONFIG_HOME/quickshell/sekaipop"
SP_HYPR_DEST="$SP_CONFIG_HOME/hypr"
SP_STATE_DIR="$SP_STATE_HOME/sekaipop"
SP_LOG_DIR="$SP_CACHE_HOME/sekaipop/installer"
SP_TIMESTAMP="$(date +%Y%m%d-%H%M%S)-$$"
SP_COLOR=0
[[ -t 1 && -z "${NO_COLOR:-}" ]] && SP_COLOR=1

sp_color() { (( SP_COLOR )) && printf '\033[%sm' "$1" || true; }
sp_info()  { printf '%s[INFO]%s %s\n' "$(sp_color '1;34')" "$(sp_color 0)" "$*"; }
sp_ok()    { printf '%s[ OK ]%s %s\n' "$(sp_color '1;32')" "$(sp_color 0)" "$*"; }
sp_warn()  { printf '%s[WARN]%s %s\n' "$(sp_color '1;33')" "$(sp_color 0)" "$*" >&2; }
sp_error() { printf '%s[FAIL]%s %s\n' "$(sp_color '1;31')" "$(sp_color 0)" "$*" >&2; }
sp_die()   { local code="${2:-1}"; sp_error "$1"; exit "$code"; }
sp_have()  { command -v "$1" >/dev/null 2>&1; }

sp_version_ge() {
    local actual="${1:-}" minimum="${2:-}" first
    [[ -n "$actual" && -n "$minimum" ]] || return 1
    first="$(printf '%s\n%s\n' "$actual" "$minimum" | sort -V | head -n1)"
    [[ "$first" == "$minimum" ]]
}

sp_confirm() {
    local question="$1" answer=''
    (( SP_YES )) && return 0
    [[ -t 0 ]] || { sp_warn "Non-interactive input: refusing unconfirmed operation: $question"; return 1; }
    read -r -p "$question [y/N] " answer
    [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]
}

sp_run() {
    if (( SP_DRY_RUN )); then
        printf '[PLAN]'; printf ' %q' "$@"; printf '\n'; return 0
    fi
    "$@"
}

sp_sudo() {
    sp_have sudo || sp_die 'sudo is required for system package/service operations.'
    sudo "$@"
}

sp_make_log() {
    (( SP_DRY_RUN || SP_CHECK || SP_PLAN || SP_NO_LOG )) && return 0
    mkdir -p "$SP_LOG_DIR"
    SP_LOG_FILE="$SP_LOG_DIR/install-$SP_TIMESTAMP.log"
    : > "$SP_LOG_FILE"
    exec > >(tee -a "$SP_LOG_FILE") 2>&1
    sp_info "Diagnostic log: $SP_LOG_FILE"
}

sp_require_normal_user() {
    local uid
    if [[ "${SEKAIPOP_TEST_MODE:-0}" == 1 && -n "${SEKAIPOP_TEST_UID:-}" ]]; then uid="$SEKAIPOP_TEST_UID"
    else uid="$(id -u)"; fi
    [[ "$uid" != 0 ]] || sp_die 'Do not run the installer as root; run it as your desktop user.'
}

sp_atomic_append_once() {
    local file="$1" line="$2" tmp parent
    parent="$(dirname "$file")"
    [[ ! -L "$file" ]] || sp_die "Refusing to append to symlinked configuration file: $file"
    [[ -d "$parent" ]] || sp_die "Configuration directory does not exist: $parent"
    [[ -f "$file" ]] && grep -Fqx -- "$line" "$file" && return 0
    tmp="$(mktemp "$parent/.sekaipop-append.XXXXXX")"
    [[ -f "$file" ]] && cat -- "$file" > "$tmp"
    printf '\n%s\n' "$line" >> "$tmp"
    if [[ -f "$file" ]]; then chmod --reference="$file" "$tmp" 2>/dev/null || chmod 0644 "$tmp"; else chmod 0644 "$tmp"; fi
    mv -f -- "$tmp" "$file"
}

sp_path_is_within() {
    local child="$1" parent="$2"
    [[ "$child" == "$parent" || "$child" == "$parent/"* ]]
}
