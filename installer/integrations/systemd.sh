#!/usr/bin/env bash

sp_run_service_action() {
    local scope="$1"
    shift
    if [[ "$scope" == system ]]; then
        sp_sudo systemctl "$@"
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
        sp_run_service_action "$scope" "${action[@]}" "$service" || \
            sp_warn "Could not ${action[*]} $scope service $service; inspect it manually."
    fi
}

sp_setup_services() {
    [[ "$SP_INIT" == systemd ]] || { sp_warn 'systemd is not active; service setup is skipped.'; return 0; }

    local service
    local -a system_services=(NetworkManager.service bluetooth.service upower.service)
    if [[ "$SP_DISTRO_ID" == fedora ]]; then
        if sp_fedora_tlp_pd_installed; then
            system_services+=(tlp.service tlp-pd.service)
        elif sp_fedora_tuned_ppd_installed; then
            system_services+=(tuned-ppd.service)
        elif sp_have rpm && rpm -q power-profiles-daemon >/dev/null 2>&1; then
            system_services+=(power-profiles-daemon.service)
        elif sp_have rpm && rpm -q tlp >/dev/null 2>&1; then
            sp_warn 'TLP is installed without tlp-pd; no PowerProfiles D-Bus provider is configured. The installer will not add a conflicting power-profile daemon.'
        else
            system_services+=(power-profiles-daemon.service)
        fi
    else
        system_services+=(power-profiles-daemon.service)
    fi
    for service in "${system_services[@]}"; do
        sp_reconcile_service system "$service"
    done

    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" || -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]]; then
        for service in pipewire.service pipewire-pulse.service wireplumber.service; do
            sp_reconcile_service user "$service"
        done
    else
        sp_warn 'No user D-Bus session detected; PipeWire user services are left untouched until a graphical login.'
    fi
}
