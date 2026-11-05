# Debian 13 (trixie)

The Debian profile uses APT. Official `trixie-backports` (main) must already be configured in the system APT sources using the Debian archive keyring. Repository configuration is administrator-managed: SekaiPop only inspects it and never creates, edits, or removes APT source files. If backports is missing or does not match the official Debian archive, installation stops with instructions to configure it manually.

Quickshell and Hyprland are individually targeted as `quickshell/trixie-backports` and `hyprland/trixie-backports`. Other packages use normal APT priorities; there is no transaction-wide `apt-get -t trixie-backports`.

Use `./install.sh --plan --profile standard` to inspect the read-only plan, then `./install.sh` to install. If the required official backports source is missing, configure it yourself and run `sudo apt update` before retrying. `--yes` never authorizes repository changes; `--no-update` is supported only when existing metadata is sufficiently current. Run `./install.sh --check` after deployment.

Hyprland >= 0.55 and Qt >= 6.7 are required. The package plan checks candidates after metadata refresh. Verify actual Qt/QML module paths and ABI compatibility on the target Debian 13 system. Container package-resolution tests do not constitute Debian VM or graphical-session certification.
