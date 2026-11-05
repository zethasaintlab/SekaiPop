#!/usr/bin/env bash
# Arch/EndeavourOS/CachyOS native package mappings. No AUR provider is enabled here.
declare -Ag DISTRO_PACKAGE_MAP=(
    [quickshell]='quickshell|quickshell-git' [hyprland]='hyprland'
    [qt6-base]='qt6-base' [qt6-declarative]='qt6-declarative' [qt6-multimedia]='qt6-multimedia-ffmpeg|qt6-multimedia'
    [qt6-svg]='qt6-svg' [qt6-imageformats]='qt6-imageformats' [qt6-wayland]='qt6-wayland' [qt6-shadertools]='qt6-shadertools'
    [dbus]='dbus' [polkit]='polkit' [graphics-egl]='mesa' [pipewire]='pipewire' [wireplumber]='wireplumber'
    [pipewire-pulse]='pipewire-pulse libpulse' [network-manager]='networkmanager' [bluetooth]='bluez bluez-utils' [upower]='upower'
    [libnotify]='libnotify' [wl-clipboard]='wl-clipboard' [jq]='jq' [curl]='curl' [git]='git'
    [xdg-utils]='xdg-utils' [xdg-user-dirs]='xdg-user-dirs' [fontconfig]='fontconfig' [util-linux]='util-linux' [diffutils]='diffutils' [procps]='procps-ng' [python3]='python'
    [python-numpy]='python-numpy'
    [portal]='xdg-desktop-portal' [portal-hyprland]='xdg-desktop-portal-hyprland' [portal-gtk]='xdg-desktop-portal-gtk'
    [xwayland]='xorg-xwayland' [noto-fonts]='noto-fonts' [noto-fonts-cjk]='noto-fonts-cjk' [noto-fonts-emoji]='noto-fonts-emoji'
    [jetbrains-mono]='ttf-jetbrains-mono' [cava]='cava' [grim]='grim' [slurp]='slurp' [cliphist]='cliphist' [wtype]='wtype'
    [hyprpicker]='hyprpicker' [imagemagick]='imagemagick' [tesseract]='tesseract tesseract-data-eng' [swappy]='swappy'
    [wf-recorder]='wf-recorder' [ffmpeg]='ffmpeg' [brightnessctl]='brightnessctl' [ddcutil]='ddcutil' [kitty]='kitty'
    [playerctl]='playerctl' [easyeffects]='easyeffects' [matugen]='matugen|matugen-bin' [hyprsunset]='hyprsunset' [power-profiles-daemon]='power-profiles-daemon'
    [gvfs]='gvfs' [keyring]='gnome-keyring' [libsecret]='libsecret' [pipewire-alsa]='pipewire-alsa' [blueman]='blueman'
    [python-aubio]='python-aubio' [songrec]='songrec' [mpvpaper]='mpvpaper' [nwg-displays]='nwg-displays'
    [hypridle]='hypridle' [nodejs]='nodejs' [pnpm]='pnpm'
)
