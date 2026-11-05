#!/usr/bin/env bash
# Debian 13 trixie. Quickshell and Hyprland are from the official trixie-backports suite.
# The installer refuses to add or rewrite APT sources; users must have backports configured.
declare -Ag DISTRO_PACKAGE_MAP=(
    [quickshell]='quickshell/trixie-backports' [hyprland]='hyprland/trixie-backports'
    [qt6-base]='qt6-base-dev-tools' [qt6-declarative]='qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-effects qml6-module-qtquick-layouts qml6-module-qtquick-shapes qml6-module-qtqml-models qml6-module-qt-labs-folderlistmodel'
    [qt6-multimedia]='qml6-module-qtmultimedia' [qt6-svg]='qt6-svg-plugins' [qt6-imageformats]='qt6-image-formats-plugins'
    [qt6-wayland]='qt6-wayland' [qt6-shadertools]='qt6-shader-baker'
    [dbus]='dbus-user-session' [polkit]='polkitd' [graphics-egl]='libegl1 libgl1' [pipewire]='pipewire' [wireplumber]='wireplumber'
    [pipewire-pulse]='pipewire-pulse pulseaudio-utils' [network-manager]='network-manager' [bluetooth]='bluez' [upower]='upower'
    [libnotify]='libnotify-bin' [wl-clipboard]='wl-clipboard' [jq]='jq' [curl]='curl' [git]='git'
    [xdg-utils]='xdg-utils' [xdg-user-dirs]='xdg-user-dirs' [fontconfig]='fontconfig' [util-linux]='util-linux' [diffutils]='diffutils' [procps]='procps' [python3]='python3' [python-numpy]='python3-numpy'
    [portal]='xdg-desktop-portal' [portal-hyprland]='xdg-desktop-portal-hyprland' [portal-gtk]='xdg-desktop-portal-gtk'
    [xwayland]='xwayland' [noto-fonts]='fonts-noto-core' [noto-fonts-cjk]='fonts-noto-cjk' [noto-fonts-emoji]='fonts-noto-color-emoji'
    [jetbrains-mono]='fonts-jetbrains-mono' [cava]='cava' [grim]='grim' [slurp]='slurp' [cliphist]='cliphist' [wtype]='wtype'
    [hyprpicker]='hyprpicker' [imagemagick]='imagemagick' [tesseract]='tesseract-ocr tesseract-ocr-eng' [swappy]='swappy'
    [wf-recorder]='wf-recorder' [ffmpeg]='ffmpeg' [brightnessctl]='brightnessctl' [ddcutil]='ddcutil' [kitty]='kitty'
    [playerctl]='playerctl' [easyeffects]='easyeffects' [matugen]='' [power-profiles-daemon]='power-profiles-daemon'
    [gvfs]='gvfs' [keyring]='gnome-keyring' [libsecret]='libsecret-1-0' [pipewire-alsa]='pipewire-alsa' [blueman]='blueman'
    [python-aubio]='python3-aubio' [songrec]='' [mpvpaper]='' [nwg-displays]='nwg-displays'
    [hypridle]='hypridle' [nodejs]='nodejs npm' [pnpm]='pnpm'
)
