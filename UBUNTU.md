# Ubuntu 26.10 (Stonking Stingray)

The Ubuntu profile uses the shared APT backend with a dedicated package map. Official Universe must already be enabled for the release, updates, and security suites using Ubuntu's supported repository-management tools. SekaiPop checks the configured official archive sources but never creates, edits, or removes APT source files. If Universe is missing or incomplete, installation stops and asks the administrator to enable it manually. No PPA or third-party archive is added.

The initial allowlist is specifically Ubuntu 26.10 (ID=ubuntu, VERSION_ID=26.10, VERSION_CODENAME=stonking), x86_64. Other releases are rejected until their package candidates and Qt/Hyprland compatibility are reviewed.

Run `./install.sh --plan --profile standard` before installation, then `./install.sh`. If Universe is missing, enable it with Ubuntu's supported repository-management tools and run `sudo apt update` before retrying. `--yes` never authorizes repository changes. `--no-update` is supported only when existing metadata is sufficiently current. Run `./install.sh --check` after deployment.

Hyprland >= 0.55 and Qt >= 6.7 are mandatory. Package candidates are resolved against the configured official Ubuntu archives; mocked tests do not certify a live Ubuntu package transaction or graphical session.
