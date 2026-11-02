#!/usr/bin/env bash
sp_qml_import_root() {
    local root cmd
    for cmd in qtpaths6 qtpaths qmake6 qmake-qt6; do
        sp_have "$cmd" || continue
        root="$("$cmd" --query QT_INSTALL_QML 2>/dev/null || "$cmd" -query QT_INSTALL_QML 2>/dev/null || true)"
        [[ -n "$root" && -d "$root" ]] && { printf '%s\n' "$root"; return 0; }
    done
    for root in /usr/lib/qt6/qml /usr/lib64/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml /usr/lib/aarch64-linux-gnu/qt6/qml; do
        [[ -d "$root" ]] && { printf '%s\n' "$root"; return 0; }
    done
    return 1
}
sp_qt_plugin_root() {
    local root cmd
    for cmd in qtpaths6 qtpaths qmake6 qmake-qt6; do
        sp_have "$cmd" || continue
        root="$("$cmd" --query QT_INSTALL_PLUGINS 2>/dev/null || "$cmd" -query QT_INSTALL_PLUGINS 2>/dev/null || true)"
        [[ -n "$root" && -d "$root" ]] && { printf '%s\n' "$root"; return 0; }
    done
    for root in /usr/lib/qt6/plugins /usr/lib64/qt6/plugins /usr/lib/x86_64-linux-gnu/qt6/plugins; do
        [[ -d "$root" ]] && { printf '%s\n' "$root"; return 0; }
    done
    return 1
}
sp_verify_quickshell() {
    local failures=0 module root path bin
    for bin in qs; do
        if sp_have "$bin"; then sp_ok "Quickshell executable: $bin"
        else sp_error "Missing Quickshell executable: $bin"; failures=$((failures + 1)); fi
    done
    root="$(sp_qml_import_root || true)"
    if [[ -z "$root" ]]; then sp_error 'Qt QML import root could not be determined.'; return 1; fi
    local -a modules=(
        Quickshell/Hyprland Quickshell/Wayland Quickshell/Io Quickshell/Widgets
        Quickshell/Services/Pam Quickshell/Services/Polkit Quickshell/Services/Notifications
        Quickshell/Services/UPower Quickshell/Services/Pipewire Quickshell/Services/Mpris Quickshell/Services/SystemTray
    )
    for module in "${modules[@]}"; do
        path="$root/$module/qmldir"
        if [[ -f "$path" ]]; then sp_ok "QML module $module"
        else sp_error "Missing QML module: $module (expected $path)"; failures=$((failures + 1)); fi
    done
    (( failures == 0 ))
}
