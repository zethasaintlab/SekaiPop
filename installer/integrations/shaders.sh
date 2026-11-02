#!/usr/bin/env bash
sp_qt_version() {
    local version cmd
    for cmd in qtpaths6 qtpaths qmake6 qmake-qt6; do
        sp_have "$cmd" || continue
        version="$("$cmd" --query QT_VERSION 2>/dev/null || "$cmd" -query QT_VERSION 2>/dev/null || true)"
        [[ -n "$version" ]] && { printf '%s\n' "$version"; return 0; }
    done
    return 1
}
sp_find_qsb() {
    local candidate
    for candidate in "$(command -v qsb 2>/dev/null || true)" /usr/lib/qt6/bin/qsb /usr/lib64/qt6/bin/qsb /usr/lib/x86_64-linux-gnu/qt6/bin/qsb /usr/lib/qt6-shadertools/bin/qsb; do
        [[ -n "$candidate" && -x "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}
sp_verify_qt_runtime() {
    local version
    version="$(sp_qt_version || true)"
    [[ -n "$version" ]] || { sp_error 'Unable to determine Qt 6 runtime version (qtpaths6/qmake6 missing).'; return 1; }
    if ! sp_version_ge "$version" 6.7.0; then sp_error "Qt $version is below SekaiPop's documented 6.7.0 minimum."; return 1; fi
    SP_QT_VERSION="$version"; sp_ok "Qt $version (minimum 6.7.0)"
}
sp_verify_qt_plugins() {
    local core="${1:-0}" root failures=0
    root="$(sp_qt_plugin_root || true)"
    [[ -n "$root" ]] || { sp_error 'Qt plugin root could not be determined.'; return 1; }
    if compgen -G "$root/imageformats/libqsvg.so" >/dev/null; then sp_ok 'Qt SVG image plugin'
    else sp_error 'Missing Qt SVG image plugin'; failures=$((failures + 1)); fi
    if (( ! core )); then
        if compgen -G "$root/imageformats/libqwebp.so" >/dev/null; then sp_ok 'Qt WebP image plugin'
        else sp_warn 'Qt WebP image plugin is unavailable; WebP wallpapers may not load.'; fi
        if compgen -G "$root/platforms/*wayland*.so" >/dev/null; then sp_ok 'Qt Wayland platform plugin'
        else sp_warn 'Qt Wayland platform plugin is unavailable; some Qt-on-Wayland integrations may not work.'; fi
    fi
    (( failures == 0 ))
}
sp_prepare_shaders() {
    local shader_dir="$1" version qsb source tmpdir compiled count=0
    [[ -d "$shader_dir" ]] || { sp_warn "Shader directory not present: $shader_dir; no shader operation needed."; return 0; }
    version="$(sp_qt_version || true)"
    [[ -n "$version" ]] || sp_die 'Qt version unavailable; cannot establish .qsb shader compatibility.'
    if sp_version_ge "$version" 6.12.0; then sp_ok "Qt $version meets SekaiPop's shipped shader baseline (6.12); prebuilt .qsb files kept."; return 0; fi
    qsb="$(sp_find_qsb || true)"
    [[ -n "$qsb" ]] || sp_die "Qt $version is older than 6.12 and qsb is missing. Install the native Qt Shader Tools package, then rerun."
    source="$shader_dir/compile-shaders.sh"
    [[ -f "$source" ]] || sp_die "Qt $version requires shader recompilation, but upstream compile-shaders.sh is missing."
    if (( SP_DRY_RUN )); then sp_info "[PLAN] Would rebuild upstream GLSL shaders with $qsb in a staging directory."; return 0; fi
    tmpdir="$(mktemp -d "${shader_dir}.stage.XXXXXX")"
    if ! cp -a "$shader_dir/." "$tmpdir/"; then rm -rf -- "$tmpdir"; sp_die 'Could not stage shader inputs; original shaders were not touched.'; fi
    if ! (cd "$tmpdir" && PATH="$(dirname "$qsb"):$PATH" bash ./compile-shaders.sh); then rm -rf -- "$tmpdir"; sp_die 'Shader compilation failed; original .qsb files were left unchanged.'; fi
    while IFS= read -r -d '' source; do
        compiled="$tmpdir/$(basename "$source").qsb"
        [[ -s "$compiled" ]] || { rm -rf -- "$tmpdir"; sp_die "Shader compiler did not produce $(basename "$compiled")."; }
        count=$((count + 1))
    done < <(find "$shader_dir" -maxdepth 1 -type f \( -name '*.vert' -o -name '*.frag' \) -print0)
    (( count > 0 )) || { rm -rf -- "$tmpdir"; sp_info 'No GLSL source shaders found; no shader rebuild was necessary.'; return 0; }
    while IFS= read -r -d '' source; do
        local target="$shader_dir/$(basename "$source").qsb" staged="$tmpdir/$(basename "$source").qsb" replacement
        replacement="$(mktemp "${target}.tmp.XXXXXX")"
        if ! install -m 0644 "$staged" "$replacement" || ! mv -f -- "$replacement" "$target"; then
            rm -f -- "$replacement"; rm -rf -- "$tmpdir"
            sp_die "Could not atomically replace shader bytecode: $target. Previous bytecode and installer snapshot are retained."
        fi
    done < <(find "$shader_dir" -maxdepth 1 -type f \( -name '*.vert' -o -name '*.frag' \) -print0)
    rm -rf -- "$tmpdir"; sp_ok "Rebuilt $count shader(s) for Qt $version using the upstream compile-shaders.sh."
}
