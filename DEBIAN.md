# Debian 13 (trixie)

The Debian profile uses APT. The administrator must configure official trixie-backports before running the installer. The installer does not modify /etc/apt/sources.list* and does not add repositories.

Quickshell and Hyprland are individually targeted as quickshell/trixie-backports and hyprland/trixie-backports. Other packages use normal APT priorities; there is no transaction-wide apt-get -t trixie-backports.

Run ./install.sh --plan --profile standard before installation, then ./install.sh --check after deployment.

Hyprland >= 0.55 and Qt >= 6.7 are required. The package plan checks candidates before transactions. Verify actual Qt/QML module paths and ABI compatibility on the target Debian 13 system. Mock tests do not constitute Debian VM or package-transaction certification.
