# Ubuntu 26.10 (Stonking Stingray)

The Ubuntu profile uses the shared APT backend with a dedicated package map. If Universe is not already configured, the installer can add a dedicated Deb822 source for the official Ubuntu archive, release updates, and security updates after confirmation. It uses the system Ubuntu archive keyring and does not rewrite existing APT source files. No PPA or third-party archive is added.

The initial allowlist is specifically Ubuntu 26.10 (ID=ubuntu, VERSION_ID=26.10, VERSION_CODENAME=stonking), x86_64. Other releases are rejected until their package candidates and Qt/Hyprland compatibility are reviewed.

Run `./install.sh --plan --profile standard` before installation, then `./install.sh`. If Universe must be enabled, the installer asks first and refreshes metadata before resolving packages. `--yes` accepts the repository prompt for unattended operation; `--no-update` cannot be used when a new source was created. Run `./install.sh --check` after deployment.

Hyprland >= 0.55 and Qt >= 6.7 are mandatory. Package candidates are resolved against the configured official Ubuntu archives; mocked tests do not certify a live Ubuntu package transaction or graphical session.
