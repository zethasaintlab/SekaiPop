#!/usr/bin/env bash

declare -ag SP_SERVICE_CHANGE_SCOPES=()
declare -ag SP_SERVICE_CHANGE_NAMES=()
declare -ag SP_SERVICE_CHANGE_ROLLBACKS=()
SP_SERVICE_TRANSACTION_ACTIVE="${SP_SERVICE_TRANSACTION_ACTIVE:-0}"
SP_SERVICE_ROLLBACK_FAILED=0

sp_service_transaction_begin() {
    SP_SERVICE_CHANGE_SCOPES=()
    SP_SERVICE_CHANGE_NAMES=()
    SP_SERVICE_CHANGE_ROLLBACKS=()
    SP_SERVICE_ROLLBACK_FAILED=0
    SP_SERVICE_TRANSACTION_ACTIVE=1
}

sp_service_transaction_commit() {
    SP_SERVICE_CHANGE_SCOPES=()
    SP_SERVICE_CHANGE_NAMES=()
    SP_SERVICE_CHANGE_ROLLBACKS=()
    SP_SERVICE_ROLLBACK_FAILED=0
    SP_SERVICE_TRANSACTION_ACTIVE=0
}

sp_service_rollback_one() {
    local scope="$1" rollback_action="$2" service="$3"
    case "$rollback_action" in
        disable-now) sp_run_service_action "$scope" disable --now "$service" ;;
        stop) sp_run_service_action "$scope" stop "$service" ;;
        *) return 2 ;;
    esac
}

sp_service_transaction_rollback() {
    local index scope service rollback_action failed=0
    for ((index=${#SP_SERVICE_CHANGE_NAMES[@]} - 1; index>=0; index--)); do
        scope="${SP_SERVICE_CHANGE_SCOPES[index]}"
        service="${SP_SERVICE_CHANGE_NAMES[index]}"
        rollback_action="${SP_SERVICE_CHANGE_ROLLBACKS[index]}"
        if ! sp_service_rollback_one "$scope" "$rollback_action" "$service"; then
            sp_warn "Could not restore the original state of $scope service $service."
            failed=1
        fi
    done
    SP_SERVICE_CHANGE_SCOPES=()
    SP_SERVICE_CHANGE_NAMES=()
    SP_SERVICE_CHANGE_ROLLBACKS=()
    SP_SERVICE_TRANSACTION_ACTIVE=0
    SP_SERVICE_ROLLBACK_FAILED="$failed"
    (( failed == 0 ))
}

sp_run_service_action() {
    local scope="$1"
    shift
    if [[ "$scope" == system ]]; then
        sp_have sudo || return 1
        sudo systemctl "$@"
    else
        systemctl --user "$@"
    fi
}

sp_reconcile_service() {
    local scope="$1" service="$2" state active prompt
    local -a systemctl_cmd=(systemctl) action=()
    [[ "$scope" == user ]] && systemctl_cmd+=(--user)

    "${systemctl_cmd[@]}" cat "$service" >/dev/null 2>&1 || return 0
    state="$("${systemctl_cmd[@]}" is-enabled "$service" 2>/dev/null || true)"
    active="$("${systemctl_cmd[@]}" is-active "$service" 2>/dev/null || true)"

    case "$state" in
        masked|masked-runtime)
            sp_warn "$scope service $service is masked; it was not unmasked or changed."
            return 0
            ;;
    esac
    [[ "$active" == active ]] && return 0

    case "$state" in
        disabled)
            action=(enable --now)
            prompt="Enable and start existing $scope service $service?"
            ;;
        enabled|enabled-runtime|linked|linked-runtime|static|indirect|generated|alias)
            action=(start)
            prompt="Start existing inactive $scope service $service?"
            ;;
        *)
            sp_warn "$scope service $service has unrecognized enablement state '${state:-unknown}' and active state '${active:-unknown}'; it was left untouched."
            return 0
            ;;
    esac

    if sp_confirm "$prompt"; then
        local rollback_action=stop rollback_index
        [[ "${action[0]}" != enable ]] || rollback_action=disable-now
        # Journal before running the operation: enable --now may partially enable
        # a unit even when its subsequent start fails.
        if (( SP_SERVICE_TRANSACTION_ACTIVE )); then
            SP_SERVICE_CHANGE_SCOPES+=("$scope")
            SP_SERVICE_CHANGE_NAMES+=("$service")
            SP_SERVICE_CHANGE_ROLLBACKS+=("$rollback_action")
        fi
        if ! sp_run_service_action "$scope" "${action[@]}" "$service"; then
            sp_warn "Could not ${action[*]} $scope service $service; attempting to restore its previous state."
            if (( SP_SERVICE_TRANSACTION_ACTIVE )); then
                if sp_service_rollback_one "$scope" "$rollback_action" "$service"; then
                    rollback_index=$(("${#SP_SERVICE_CHANGE_NAMES[@]}" - 1))
                    unset "SP_SERVICE_CHANGE_SCOPES[rollback_index]" \
                        "SP_SERVICE_CHANGE_NAMES[rollback_index]" \
                        "SP_SERVICE_CHANGE_ROLLBACKS[rollback_index]"
                else
                    SP_SERVICE_ROLLBACK_FAILED=1
                    sp_warn "Immediate rollback failed for $scope service $service; the deployment transaction must roll back."
                    return 1
                fi
            fi
        fi
    fi
}

sp_setup_services() {
    [[ "$SP_INIT" == systemd ]] || { sp_warn 'systemd is not active; service setup is skipped.'; return 0; }

    local service failed=0 active_provider="" active_providers="" active_count=0 provider_unit package_provider_count=0 tlp_backend_active=0 tlp_provider_conflict=0
    local -a system_services=(NetworkManager.service bluetooth.service upower.service)
    if [[ "${SP_DISTRO_ID:-}" == fedora ]]; then
        # Prefer a provider that is already active over package-install order. This
        # prevents an inactive second provider from being started beside the live one.
        for provider_unit in tlp-pd.service tuned-ppd.service power-profiles-daemon.service; do
            if systemctl is-active --quiet "$provider_unit"; then
                active_provider="$provider_unit"
                active_providers+="$provider_unit "
                ((active_count += 1))
            fi
        done
        systemctl is-active --quiet tlp.service && tlp_backend_active=1 || true
        if (( tlp_backend_active )) &&
            [[ -n "$active_provider" && "$active_provider" != "tlp-pd.service" ]]; then
            tlp_provider_conflict=1
        fi

        if (( active_count > 1 )); then
            sp_warn "Multiple Fedora PowerProfiles providers are already active (${active_providers% }); no provider service will be changed."
        elif (( tlp_provider_conflict )); then
            sp_warn "The TLP backend is active alongside a different PowerProfiles provider ($active_provider); no provider service will be changed."
        elif [[ "$active_provider" == tlp-pd.service ]]; then
            system_services+=(tlp.service tlp-pd.service)
        elif [[ "$active_provider" == tuned-ppd.service ]]; then
            system_services+=(tuned.service tuned-ppd.service)
        elif [[ "$active_provider" == power-profiles-daemon.service ]]; then
            system_services+=(power-profiles-daemon.service)
        elif sp_fedora_power_profile_api_available; then
            : # An unrecognized provider already owns the PowerProfiles D-Bus API; never start a second adapter.
        elif (( tlp_backend_active )) && ! sp_fedora_tlp_pd_installed; then
            sp_warn 'TLP is active without tlp-pd; no TuneD/PPD provider will be started alongside it. Install/configure one power-management stack explicitly before rerunning SekaiPop.'
        elif (( tlp_backend_active )) && sp_fedora_tlp_pd_installed; then
            system_services+=(tlp.service tlp-pd.service)
        else
            package_provider_count="$(sp_fedora_power_profile_provider_count || printf '0')"
            if (( package_provider_count > 1 )); then
                sp_warn 'Multiple Fedora PowerProfiles provider packages are installed but none is active; all provider services were left untouched. Select one provider manually before rerunning SekaiPop.'
            elif sp_fedora_tlp_pd_installed; then
                system_services+=(tlp.service tlp-pd.service)
            elif sp_fedora_tuned_ppd_installed; then
                system_services+=(tuned.service tuned-ppd.service)
            elif sp_have rpm && rpm -q power-profiles-daemon >/dev/null 2>&1; then
                system_services+=(power-profiles-daemon.service)
            elif sp_fedora_tlp_installed; then
                sp_warn 'TLP is installed without tlp-pd; no PowerProfiles D-Bus provider is configured. The installer will not add a conflicting power-profile daemon.'
            else
                system_services+=(power-profiles-daemon.service)
            fi
        fi
    else
        system_services+=(power-profiles-daemon.service)
    fi
    for service in "${system_services[@]}"; do
        sp_reconcile_service system "$service" || failed=1
    done
    if [[ "${SP_DISTRO_ID:-}" == fedora ]] &&
        sp_fedora_power_profile_provider_installed &&
        ! sp_fedora_power_profile_api_available; then
        sp_warn 'A Fedora power-profile provider package is installed, but the PowerProfiles D-Bus API is not active. Power-profile controls may remain unavailable; inspect the selected provider service.'
    fi

    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" || -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]]; then
        for service in pipewire.service pipewire-pulse.service wireplumber.service; do
            sp_reconcile_service user "$service" || failed=1
        done
    else
        sp_warn 'No user D-Bus session detected; PipeWire user services are left untouched until a graphical login.'
    fi
    return "$failed"
}
