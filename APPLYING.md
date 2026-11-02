# Applying the multi-distro installer

The installer is integrated into this complete SekaiPop repository and uses the SekaiPop runtime tree as its source of truth. The existing sekaipop/, hypr/, assets, plugins, docs, and examples remain in place.

Canonical root entrypoints are install.sh, install-deps.sh, and check-deps.sh. install-multi.sh remains only as a deprecated compatibility wrapper. Do not add back the legacy root-level install-fedora.sh, install-deps-fedora.sh, or check-deps-fedora.sh wrappers.

Supported distribution IDs and release gates are explicit. Do not add ID_LIKE fallback. Add another distribution only after reviewing package mappings, Qt/QML import paths, Hyprland >= 0.55 availability, Quickshell packaging, service integration, and actual VM behavior.

Package source policy is conservative: no automatic AUR, COPR, PPA, arbitrary repository, or remote source-build activation. --plan must remain read-only. Any package transaction, configuration replacement, service enablement, or compositor activation must have explicit scope and preserve user-owned data.
