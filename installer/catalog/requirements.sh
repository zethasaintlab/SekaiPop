#!/usr/bin/env bash
# Logical capability catalog. Distro profiles map IDs to one or more native packages.
# Core is the minimum runtime needed for the shell itself; Standard adds the normal
# SekaiPop feature set; Desktop is the optional bare-Hyprland convenience layer.

declare -ag SP_REQ_CORE=(
    quickshell hyprland qt6-base qt6-declarative qt6-multimedia qt6-svg
    dbus polkit graphics-egl pipewire wireplumber pipewire-pulse network-manager bluetooth upower
    libnotify wl-clipboard jq curl git xdg-utils fontconfig
)
declare -ag SP_REQ_STANDARD=(
    qt6-imageformats qt6-wayland xdg-user-dirs python3 python-numpy
    cava grim slurp cliphist wtype hyprpicker imagemagick tesseract swappy wf-recorder ffmpeg
    brightnessctl ddcutil kitty playerctl easyeffects matugen hyprsunset power-profiles-daemon
)
declare -ag SP_REQ_DESKTOP=(
    portal portal-hyprland portal-gtk xwayland noto-fonts noto-fonts-cjk noto-fonts-emoji nerd-font
    material-symbols google-sans-flex gvfs keyring libsecret pipewire-alsa blueman
)
declare -ag SP_REQ_FULL=(python-aubio songrec mpvpaper nwg-displays hypridle nodejs pnpm)

declare -Ag SP_REQ_MIN_VERSION=(
    [hyprland]='0.55.0'
    [qt6-base]='6.7.0'
    [matugen]='2.0.0'
)

declare -Ag SP_REQ_DESCRIPTION=(
    [quickshell]='Quickshell executable and SekaiPop QML modules'
    [hyprland]='Hyprland compositor >= 0.55.0 with the Lua configuration API'
    [qt6-base]='Qt 6 runtime >= 6.7'
    [qt6-declarative]='Qt QML/Quick runtime and required QML imports'
    [qt6-multimedia]='Qt Multimedia QML module'
    [qt6-svg]='Qt SVG image plugin'
    [qt6-shadertools]='Qt Shader Tools/qsb; required only when rebuilding the shipped Qt 6.12 shader bytecode on Qt < 6.12'
    [qt6-imageformats]='Qt image format plugins, including WebP'
    [qt6-wayland]='Qt Wayland platform plugin'
    [dbus]='D-Bus user/system session support'
    [polkit]='PolicyKit daemon/runtime'
    [graphics-egl]='EGL/OpenGL userspace runtime; existing GPU drivers are preserved'
    [pipewire]='PipeWire server'
    [wireplumber]='WirePlumber session manager'
    [pipewire-pulse]='PulseAudio-compatible PipeWire server and client utilities'
    [network-manager]='NetworkManager and nmcli'
    [bluetooth]='BlueZ and bluetoothctl'
    [upower]='UPower and battery state'
    [libnotify]='notify-send notification client'
    [wl-clipboard]='Wayland clipboard CLI'
    [jq]='jq JSON processor'
    [curl]='curl HTTP client'
    [git]='git source/version metadata'
    [xdg-utils]='xdg-open and desktop integration utilities'
    [xdg-user-dirs]='xdg-user-dir support'
    [fontconfig]='fc-list/fc-cache font discovery and cache'
    [python3]='Python 3 runtime for optional audio-analysis integration'
    [python-numpy]='NumPy module for the audio analyzer; the shell has a fallback'
    [ffmpeg]='FFmpeg executable for video thumbnails and audio capture'
    [power-profiles-daemon]='Power profile D-Bus API via powerprofilesctl or Fedora tuned-ppd compatibility service'
    [hyprsunset]='Hyprland night-light / gamma utility'
    [material-symbols]='Material Symbols Rounded font used by SekaiPop icons'
    [google-sans-flex]='Google Sans Flex font used by the SekaiPop interface'
)

sp_describe_requirement() {
    local id="$1"
    printf '%s' "${SP_REQ_DESCRIPTION[$id]:-$id}"
}
