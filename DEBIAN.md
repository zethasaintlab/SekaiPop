# Debian 13 (trixie)

The Debian profile uses APT. If official `trixie-backports` is not already configured, the installer can add a dedicated Deb822 source for the official Debian archive after confirmation. It uses the system Debian archive keyring, refreshes APT metadata, and rolls back the newly created source file if metadata refresh fails. Existing APT source files are not rewritten.

Quickshell and Hyprland are individually targeted as `quickshell/trixie-backports` and `hyprland/trixie-backports`. Other packages use normal APT priorities; there is no transaction-wide `apt-get -t trixie-backports`.

Use `./install.sh --plan --profile standard` to inspect the read-only plan, then `./install.sh` to install. If repository bootstrap is required, the installer asks before changing APT configuration. `--yes` accepts this prompt for unattended operation; `--no-update` is incompatible with a newly added source. Run `./install.sh --check` after deployment.

Hyprland >= 0.55 and Qt >= 6.7 are required. The package plan checks candidates after metadata refresh. Verify actual Qt/QML module paths and ABI compatibility on the target Debian 13 system. Container package-resolution tests do not constitute Debian VM or graphical-session certification.
