# Static dependency audit

Generated from the project source tree using tools/audit-dependencies.py. The CI run scanned 389 QML files and 85 installer/project shell scripts. This is a source-reference inventory, not proof that every dynamically constructed command or runtime plugin has been captured.

## QML import inventory

| Module | Files | Runtime provider |
|---|---:|---|
| QtQuick | 389 | Qt 6 Declarative |
| QtQuick.Controls.impl | 1 | Qt 6 Declarative / Quick Controls runtime; private implementation import |
| QtQuick.Effects | 17 | Qt 6 Declarative |
| QtQuick.Layouts | 6 | Qt 6 Declarative |
| QtQuick.Shapes | 10 | Qt 6 Declarative |
| Qt.labs.folderlistmodel | 4 | Qt 6 Declarative |
| QtQml.Models | 1 | Qt 6 Declarative |
| QtMultimedia | 1 | Qt 6 Multimedia |
| Quickshell and Quickshell.* | 315+ across modules | Quickshell package and its built modules |
| qs.modules.* / qs.services | internal imports | SekaiPop deployment tree; not external packages |

The Qt Declarative runtime is mapped as qt6-qtdeclarative on Fedora, qt6-declarative-dev plus the runtime QML module packages on Debian/Ubuntu, and qt6-declarative on Arch. Qt Multimedia is mapped to qt6-qtmultimedia, qt6-multimedia-dev/qml6-module-qtmultimedia, or qt6-multimedia-ffmpeg/qt6-multimedia as appropriate. The installer does not install Qt development headers on Fedora merely to satisfy runtime QML imports.

## Explicit executable references in QML

| Executable / command | Capability or treatment |
|---|---|
| qs | Quickshell runtime |
| hyprctl | Hyprland runtime |
| nmcli | NetworkManager |
| bluetoothctl | BlueZ |
| notify-send | libnotify |
| pactl | PipeWire PulseAudio compatibility tools |
| wpctl | WirePlumber tools |
| pkexec | polkit |
| wl-copy | wl-clipboard |
| xdg-open | xdg-utils |
| cliphist | Standard clipboard-history feature |
| ddcutil | Standard monitor-control feature |
| hyprpicker | Standard color-picker feature |
| nwg-displays | Full profile display-layout utility |
| python3 | Standard Python integration |
| pkill | procps; used by clipboard process cleanup |
| setpriv / setsid | util-linux |
| systemd-inhibit | systemd |
| curl | HTTP client |
| bash / sh | base shell interpreters |
| cat / mkdir / nice / uname | base userland utilities |
| warp-cli | Optional third-party Cloudflare WARP client; never installed by this project |
| set_property | mpv IPC method in MpvpaperWallpaper.qml, not an executable dependency |

## Shell integration probes

Shell scripts also probe for optional desktop/application tools such as checkupdates, paru, yay, dolphin, discord/equibop/vesktop, dconf, gsettings, dbus-send, gdbus, kwriteconfig5/6, plasma-apply-colorscheme, qt5ct/qt6ct, xrdb, hypridle, matugen, mpvpaper, songrec, node, pnpm and others. These are feature-specific integrations or user-installed applications; the installer does not claim to install every optional application or KDE/X11 helper in every distro profile.

## Package catalog decisions

- util-linux is part of the core profile because the installer uses flock for transaction serialization and the shell uses setpriv/setsid.
- procps is part of the standard profile because clipboard cleanup invokes pkill.
- Arch maps JetBrains Mono to ttf-jetbrains-mono, not a Nerd Font package. The font capability is deliberately named jetbrains-mono on all distros.
- FFmpeg capability detection verifies the ffmpeg executable only; it does not assert that a given codec is available.
- PowerProfiles is verified by the actual D-Bus name and exported interface, not by a client executable alone.
- Qt Shader Tools is conditional: it is mandatory when the effective Qt version is below 6.12 and the shipped shader bytecode must be rebuilt.
- No automatic provider is configured for Cloudflare WARP, AUR helpers, COPRs, PPAs, or unpinned source builds.

## Re-running the audit

    python3 tools/audit-dependencies.py
    python3 tools/audit-dependencies.py --format tsv

Review new command references whenever QML or shell code changes. The scanner intentionally does not attempt to parse arbitrary JavaScript string construction, shell eval, D-Bus payloads, generated commands, or all transitive executable invocations.