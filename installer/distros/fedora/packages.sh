#!/usr/bin/env bash
# Fedora 44 baseline mappings, shared with Fedora 45 where candidates are verified. No COPR is enabled; Hyprland must already be installed
# from a repository the user independently selected and trusts.
declare -Ag DISTRO_PACKAGE_MAP=(
    [quickshell]='quickshell' [hyprland]=''
    [qt6-base]='qt6-qtbase' [qt6-declarative]='qt6-qtdeclarative' [qt6-multimedia]='qt6-qtmultimedia'
    [qt6-svg]='qt6-qtsvg' [qt6-imageformats]='qt6-qtimageformats' [qt6-wayland]='qt6-qtwayland' [qt6-shadertools]='qt6-qtshadertools'
    [dbus]='dbus-daemon' [polkit]='polkit' [graphics-egl]='libglvnd-egl' [pipewire]='pipewire' [wireplumber]='wireplumber'
    [pipewire-pulse]='pipewire-pulseaudio pulseaudio-utils' [network-manager]='NetworkManager' [bluetooth]='bluez' [upower]='upower'
    [libnotify]='libnotify' [wl-clipboard]='wl-clipboard' [jq]='jq' [curl]='curl' [git]='git-core'
    [xdg-utils]='xdg-utils' [xdg-user-dirs]='xdg-user-dirs' [fontconfig]='fontconfig' [python3]='python3'
    [python-numpy]='python3-numpy'
    [portal]='xdg-desktop-portal' [portal-hyprland]='' [portal-gtk]='xdg-desktop-portal-gtk'
    [xwayland]='xorg-x11-server-Xwayland' [noto-fonts]='google-noto-sans-fonts' [noto-fonts-cjk]='google-noto-cjk-fonts'
    [noto-fonts-emoji]='google-noto-emoji-fonts' [jetbrains-mono]='jetbrains-mono-fonts' [cava]='cava' [grim]='grim' [slurp]='slurp'
    [cliphist]='cliphist' [wtype]='wtype' [hyprpicker]='hyprpicker' [imagemagick]='ImageMagick' [tesseract]='tesseract'
    [swappy]='swappy' [wf-recorder]='wf-recorder' [ffmpeg]='ffmpeg-free' [brightnessctl]='brightnessctl' [ddcutil]='ddcutil'
    [kitty]='kitty' [playerctl]='playerctl' [easyeffects]='easyeffects' [matugen]='matugen' [power-profiles-daemon]='tuned-ppd'
    [gvfs]='gvfs' [keyring]='gnome-keyring' [libsecret]='libsecret' [pipewire-alsa]='pipewire-alsa' [blueman]='blueman'
    [python-aubio]='python3-aubio' [songrec]='' [mpvpaper]='' [nwg-displays]='nwg-displays'
    [hypridle]='hypridle' [nodejs]='nodejs' [pnpm]='pnpm'
)

# Fedora 45 currently exposes tuned-ppd in testing updates, not as a verified stable candidate.
# Preserve an already-installed/active provider, but do not request an unverified package.
if [[ "${SP_DISTRO_VERSION:-}" == 45 ]]; then
    DISTRO_PACKAGE_MAP[power-profiles-daemon]=''
fi
