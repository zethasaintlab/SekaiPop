#!/usr/bin/env bash
sp_setup_services() {
    [[ "$SP_INIT" == systemd ]] || { sp_warn 'systemd is not active; service setup is skipped.'; return 0; }
    local service state active
    local -a system_services=(NetworkManager.service bluetooth.service upower.service power-profiles-daemon.service)
    for service in "${system_services[@]}"; do
        systemctl cat "$service" >/dev/null 2>&1 || continue
        state="$(systemctl is-enabled "$service" 2>/dev/null || true)"
        active="$(systemctl is-active "$service" 2>/dev/null || true)"
        [[ "$state" == enabled || "$state" == enabled-runtime || "$state" == static || "$state" == indirect || "$state" == generated || "$active" == active ]] && continue
        [[ "$state" == masked || "$state" == masked-runtime ]] && { sp_warn "$service is masked by the user/system; it was not unmasked."; continue; }
        if sp_confirm "Enable and start existing system service $service?"; then sp_sudo systemctl enable --now "$service" || sp_warn "Could not enable $service; inspect it manually."; fi
    done
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" || -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]]; then
        for service in pipewire.service pipewire-pulse.service wireplumber.service; do
            systemctl --user cat "$service" >/dev/null 2>&1 || continue
            state="$(systemctl --user is-enabled "$service" 2>/dev/null || true)"
            active="$(systemctl --user is-active "$service" 2>/dev/null || true)"
            [[ "$state" == enabled || "$state" == enabled-runtime || "$state" == static || "$state" == indirect || "$state" == generated || "$active" == active ]] && continue
            [[ "$state" == masked || "$state" == masked-runtime ]] && { sp_warn "User service $service is masked; left untouched."; continue; }
            if sp_confirm "Enable and start existing user service $service?"; then systemctl --user enable --now "$service" || sp_warn "Could not enable user service $service."; fi
        done
    else sp_warn 'No user D-Bus session detected; PipeWire user services are left untouched until a graphical login.'; fi
}
