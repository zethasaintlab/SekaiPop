# Ubuntu 26.10 (Stonking Stingray)

The Ubuntu profile uses the shared APT backend with a dedicated package map. Ubuntu Universe must already be enabled; the installer does not add PPAs or edit APT sources.

The initial allowlist is specifically Ubuntu 26.10 (ID=ubuntu, VERSION_ID=26.10, VERSION_CODENAME=stonking), x86_64. Other releases are rejected until their package candidates and Qt/Hyprland compatibility are reviewed.

Run ./install.sh --plan --profile standard before installation, then ./install.sh --check after deployment.

Hyprland >= 0.55 and Qt >= 6.7 are mandatory. Confirm package candidates on a target installation; mocked tests do not certify a live Ubuntu package transaction or graphical session.
